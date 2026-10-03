import 'dart:async';
import 'dart:math';

/// 检查响应是否表明可能遇到了限频或 WAF 拦截
bool isRateLimitedResponse({
  int? statusCode,
  String? responseBody,
  String? location,
}) {
  if (statusCode == 429) return true;
  if (statusCode == 403 || statusCode == 503) {
    if (responseBody != null) {
      final lower = responseBody.toLowerCase();
      if (lower.contains('rate limit') ||
          lower.contains('too many requests') ||
          lower.contains('限频') ||
          lower.contains('访问过于频繁') ||
          lower.contains('waf') ||
          lower.contains('captcha_error') ||
          lower.contains('验证码')) {
        return true;
      }
    }
  }
  return false;
}

class HostThrottleState {
  final String host;
  final int maxConcurrency;
  final Duration minInterval;
  final Random _random;

  int inFlight = 0;
  DateTime lastStartTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int backoffAttempt = 0;

  final List<Completer<void>> queue = [];

  HostThrottleState({
    required this.host,
    this.maxConcurrency = 3,
    this.minInterval = const Duration(milliseconds: 250),
    Random? random,
  }) : _random = random ?? Random();

  Duration nextIntervalWithJitter() {
    // 基础间隔 ~250ms，附加小幅随机抖动
    final jitterMs = _random.nextInt(61) - 30; // -30ms ~ +30ms
    final totalMs = max(100, minInterval.inMilliseconds + jitterMs);
    return Duration(milliseconds: totalMs);
  }
}

/// 针对单 Host 的请求限频与并发削峰控制器（Pure Dart，便于单元测试与跨端复用）
class RequestThrottle {
  static final RequestThrottle instance = RequestThrottle();

  final Map<String, HostThrottleState> _hosts = {};
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final Random _random;

  RequestThrottle({
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    Random? random,
  })  : _clock = clock ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed,
        _random = random ?? Random();

  HostThrottleState _getState(
    String host, {
    int maxConcurrency = 3,
    Duration minInterval = const Duration(milliseconds: 250),
  }) {
    return _hosts.putIfAbsent(
      host,
      () => HostThrottleState(
        host: host,
        maxConcurrency: maxConcurrency,
        minInterval: minInterval,
        random: _random,
      ),
    );
  }

  /// 获取许可。等待在队列中的时长不会计入调用方的请求超时配额。
  Future<void> acquire(
    String host, {
    int maxConcurrency = 3,
    Duration minInterval = const Duration(milliseconds: 250),
  }) async {
    final state = _getState(
      host,
      maxConcurrency: maxConcurrency,
      minInterval: minInterval,
    );

    // 1. 若当前活跃请求数达到上限，FIFO 进入等待队列
    if (state.inFlight >= state.maxConcurrency) {
      final completer = Completer<void>();
      state.queue.add(completer);
      await completer.future;
    }

    // 2. 检查并等待退避期（若因 429/限频正处于退避中）
    final now = _clock();
    if (state.backoffUntil.isAfter(now)) {
      final waitDuration = state.backoffUntil.difference(now);
      await _delay(waitDuration);
    }

    // 3. 削峰：保证请求启动的最小间隔
    final nowAfterBackoff = _clock();
    final elapsedSinceLastStart =
        nowAfterBackoff.difference(state.lastStartTime);
    final targetInterval = state.nextIntervalWithJitter();
    if (elapsedSinceLastStart < targetInterval) {
      final spacingWait = targetInterval - elapsedSinceLastStart;
      await _delay(spacingWait);
    }

    state.inFlight++;
    state.lastStartTime = _clock();
  }

  /// 释放并发许可
  void release(String host) {
    final state = _hosts[host];
    if (state == null) return;

    state.inFlight = max(0, state.inFlight - 1);
    if (state.queue.isNotEmpty) {
      final next = state.queue.removeAt(0);
      next.complete();
    }
  }

  /// 记录遭遇限频或退避触发，设置下一次指数退避时间
  void recordRateLimit(
    String host, {
    Duration baseBackoff = const Duration(milliseconds: 1500),
  }) {
    final state = _hosts[host];
    if (state == null) return;

    state.backoffAttempt++;
    final multiplier = pow(2, min(state.backoffAttempt - 1, 3)).toDouble();
    final backoffMs =
        min(8000.0, baseBackoff.inMilliseconds * multiplier).toInt();
    final jitterMs = _random.nextInt(200);
    state.backoffUntil =
        _clock().add(Duration(milliseconds: backoffMs + jitterMs));
  }

  /// 请求成功后重置退避状态
  void recordSuccess(String host) {
    final state = _hosts[host];
    if (state == null) return;
    if (state.backoffAttempt > 0) {
      state.backoffAttempt = 0;
      state.backoffUntil = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// 包装并安全执行带削峰的请求
  Future<T> run<T>(
    String host,
    Future<T> Function() action, {
    int maxConcurrency = 3,
    Duration minInterval = const Duration(milliseconds: 250),
  }) async {
    await acquire(
      host,
      maxConcurrency: maxConcurrency,
      minInterval: minInterval,
    );
    try {
      final result = await action();
      recordSuccess(host);
      return result;
    } catch (e) {
      rethrow;
    } finally {
      release(host);
    }
  }
}

