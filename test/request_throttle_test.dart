import 'package:celechron/http/zjuServices/request_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestThrottle Unit Tests', () {
    test('isRateLimitedResponse identifies 429 and rate limit hints', () {
      expect(isRateLimitedResponse(statusCode: 429), isTrue);
      expect(
          isRateLimitedResponse(statusCode: 403, responseBody: '请求过于频繁，请稍后再试'),
          isTrue);
      expect(
          isRateLimitedResponse(
              statusCode: 503, responseBody: 'waf rate limit triggered'),
          isTrue);
      expect(
          isRateLimitedResponse(statusCode: 403, responseBody: 'captcha_error'),
          isTrue);
      expect(
          isRateLimitedResponse(statusCode: 200, responseBody: 'ok'), isFalse);
      expect(
          isRateLimitedResponse(
              statusCode: 403, responseBody: 'unauthorized permission'),
          isFalse);
    });

    test('enforces max concurrency and releases permits on completion',
        () async {
      var currentTime = DateTime(2026, 10, 1, 10, 0, 0);
      final throttle = RequestThrottle(
        clock: () => currentTime,
        delay: (d) async {
          currentTime = currentTime.add(d);
        },
      );

      final running = <int>[];
      final maxObservedRunning = <int>[];
      var currentRunning = 0;

      Future<void> simulateTask(int id) async {
        await throttle.run(
          'test.host',
          () async {
            currentRunning++;
            maxObservedRunning.add(currentRunning);
            running.add(id);
            // 模拟执行一段任务
            await Future<void>.delayed(const Duration(milliseconds: 10));
            currentRunning--;
          },
          maxConcurrency: 2,
          minInterval: const Duration(milliseconds: 50),
        );
      }

      await Future.wait([
        simulateTask(1),
        simulateTask(2),
        simulateTask(3),
        simulateTask(4),
      ]);

      expect(maxObservedRunning.every((count) => count <= 2), isTrue);
      expect(running.length, equals(4));
    });

    test('releases permit even when action throws', () async {
      var currentTime = DateTime(2026, 10, 1, 10, 0, 0);
      final throttle = RequestThrottle(
        clock: () => currentTime,
        delay: (d) async {},
      );

      expect(
        () => throttle.run(
          'test.host',
          () async => throw StateError('simulated error'),
          maxConcurrency: 1,
        ),
        throwsStateError,
      );

      // 释放后下一个请求能够立即执行
      var executed = false;
      await throttle.run(
        'test.host',
        () async {
          executed = true;
        },
        maxConcurrency: 1,
        minInterval: Duration.zero,
      );
      expect(executed, isTrue);
    });

    test('triggers backoff on rate limit and recovers on success', () async {
      var currentTime = DateTime(2026, 10, 1, 10, 0, 0);
      var delayedDuration = Duration.zero;

      final throttle = RequestThrottle(
        clock: () => currentTime,
        delay: (d) async {
          delayedDuration += d;
          currentTime = currentTime.add(d);
        },
      );

      throttle.recordRateLimit('test.host',
          baseBackoff: const Duration(milliseconds: 1000));

      await throttle.acquire(
        'test.host',
        maxConcurrency: 3,
        minInterval: Duration.zero,
      );
      throttle.release('test.host');

      // 应该至少经历了 ~1000ms 的退避等待
      expect(delayedDuration.inMilliseconds, greaterThanOrEqualTo(1000));

      // 成功后重置退避状态
      throttle.recordSuccess('test.host');
      delayedDuration = Duration.zero;

      await throttle.acquire(
        'test.host',
        maxConcurrency: 3,
        minInterval: Duration.zero,
      );
      throttle.release('test.host');
      expect(delayedDuration.inMilliseconds, equals(0));
    });
  });
}
