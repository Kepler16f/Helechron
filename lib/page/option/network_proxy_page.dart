import 'dart:async';
import 'dart:io';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/http/zjuServices/network_defense.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NetworkProxyPage extends StatefulWidget {
  const NetworkProxyPage({super.key});

  @override
  State<NetworkProxyPage> createState() => _NetworkProxyPageState();
}

class _NetworkProxyPageState extends State<NetworkProxyPage> {
  late bool _forceZjuDirect;
  late bool _globalDirect;

  bool _isTesting = false;
  final Map<String, _DiagnosticItemResult> _diagnosticResults = {};

  static const List<_DiagnosticTarget> _targets = [
    _DiagnosticTarget(
      id: 'zjuam',
      name: '统一身份认证 (ZJUAM)',
      url: 'https://zjuam.zju.edu.cn/cas/login',
      description: '登录、SSO单点认证核心网关',
    ),
    _DiagnosticTarget(
      id: 'courses',
      name: '学在浙大 (Courses)',
      url: 'https://courses.zju.edu.cn/api/users/current',
      description: '作业、小测、课件与教学互动',
    ),
    _DiagnosticTarget(
      id: 'classroom',
      name: '智云课堂 (Classroom)',
      url: 'https://classroom.zju.edu.cn',
      description: '课程回放、课堂直播与讲义',
    ),
    _DiagnosticTarget(
      id: 'zdbk',
      name: '本科生教务网 (ZDBK)',
      url: 'https://zdbk.zju.edu.cn/jwglxt/xtgl/login_sso.html',
      description: '课表、考试、成绩与学分查询',
    ),
    _DiagnosticTarget(
      id: 'eta',
      name: '校务与服务中心 (ETA)',
      url: 'https://eta.zju.edu.cn',
      description: '学籍信息、学生事务与校内流程',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _forceZjuDirect = isForceZjuDirectEnabled();
    _globalDirect = isGlobalDirectEnabled();
  }

  Future<void> _runDiagnostics() async {
    if (_isTesting) return;
    setState(() {
      _isTesting = true;
      _diagnosticResults.clear();
      for (final t in _targets) {
        _diagnosticResults[t.id] = _DiagnosticItemResult(
          state: _DiagnosticState.testing,
          message: '正在探测建连与响应...',
        );
      }
    });

    final futures = _targets.map((t) async {
      final result = await _probeTarget(t.url);
      if (mounted) {
        setState(() {
          _diagnosticResults[t.id] = result;
        });
      }
    });

    await Future.wait(futures);

    if (mounted) {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<_DiagnosticItemResult> _probeTarget(String urlStr) async {
    final stopwatch = Stopwatch()..start();
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      applyZjuNetworkDefense(
        client,
        connectionTimeout: const Duration(seconds: 8),
      );

      final uri = Uri.parse(urlStr);
      final req = await client.getUrl(uri);
      req.followRedirects = false; // 探测第一跳真实响应
      final resp = await req.close();
      stopwatch.stop();

      final statusCode = resp.statusCode;
      final ms = stopwatch.elapsedMilliseconds;

      if (statusCode == 200 || statusCode == 302 || statusCode == 301) {
        return _DiagnosticItemResult(
          state: _DiagnosticState.success,
          latencyMs: ms,
          statusCode: statusCode,
          message: '连通正常 (HTTP $statusCode, ${ms}ms)',
        );
      } else if (statusCode == 403) {
        return _DiagnosticItemResult(
          state: _DiagnosticState.blocked,
          latencyMs: ms,
          statusCode: statusCode,
          message: '被拦截 (HTTP 403 - 疑似触发海外IP防火墙/WAF)',
        );
      } else {
        return _DiagnosticItemResult(
          state: _DiagnosticState.warning,
          latencyMs: ms,
          statusCode: statusCode,
          message: '状态异常 (HTTP $statusCode, ${ms}ms)',
        );
      }
    } on SocketException catch (e) {
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      final isTimeout =
          e.message.contains('timed out') ||
          e.osError?.message.contains('timed out') == true;
      return _DiagnosticItemResult(
        state: _DiagnosticState.error,
        latencyMs: ms,
        message: isTimeout
            ? '连接超时 (${ms}ms，可能被节点代理丢弃或路由黑洞)'
            : '网络连接失败: ${e.message}',
      );
    } catch (e) {
      stopwatch.stop();
      return _DiagnosticItemResult(
        state: _DiagnosticState.error,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: '探测失败: $e',
      );
    } finally {
      client?.close(force: true);
    }
  }

  void _copyToClipboard(String content, String title) {
    Clipboard.setData(ClipboardData(text: content));
    showAelAlertDialog(
      context: context,
      title: title,
      message: '规则内容已复制到剪贴板，请前往您的代理客户端（如 Clash、Sing-box 等）粘贴到分流规则列表中并置于最前。',
      confirmLabel: '好的',
    );
  }

  static const String _clashRules =
      '''# ==========================================
# 浙大校内直连分流规则（请置于任何 PROXY 规则之前）
# ==========================================
- DOMAIN-SUFFIX,zju.edu.cn,DIRECT
- DOMAIN-KEYWORD,zju,DIRECT
- DOMAIN-SUFFIX,cc98.org,DIRECT
- DOMAIN-SUFFIX,nexushd.org,DIRECT
- IP-CIDR,210.32.0.0/16,DIRECT,no-resolve
- IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
- IP-CIDR,172.16.0.0/12,DIRECT,no-resolve''';

  static const String _singboxRules = '''{
  "route": {
    "rules": [
      {
        "domain_suffix": [
          "zju.edu.cn",
          "cc98.org",
          "nexushd.org"
        ],
        "domain_keyword": [
          "zju"
        ],
        "ip_cidr": [
          "210.32.0.0/16",
          "10.0.0.0/8",
          "172.16.0.0/12"
        ],
        "outbound": "direct"
      }
    ]
  }
}''';

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '网络代理与校内直连'),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AelSpacing.pageHorizontal,
                vertical: AelSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: AelConstrainedWidth(
                  maxWidth: AelBreakpointSpec.maxDetailWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AelSectionCard(
                        title: 'App 内网络直连防御',
                        icon: AelIcons.wifi,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AelSwitchTile(
                              icon: AelIcons.shield,
                              badgeStyle: AelIconBadgeStyle.circle,
                              title: '校内服务强制直连',
                              subtitle: '针对 *.zju.edu.cn 等校内域名强制 DIRECT',
                              value: _forceZjuDirect,
                              onChanged: (val) async {
                                await setForceZjuDirectEnabled(val);
                                setState(() => _forceZjuDirect = val);
                              },
                            ),
                            const SizedBox(height: AelSpacing.xs),
                            Container(height: 0.5, color: colors.divider),
                            const SizedBox(height: AelSpacing.xs),
                            AelSwitchTile(
                              icon: AelIcons.globe,
                              badgeStyle: AelIconBadgeStyle.circle,
                              title: '全局直连模式',
                              subtitle: 'App 内所有网络请求均不走系统 HTTP 代理',
                              value: _globalDirect,
                              onChanged: (val) async {
                                await setGlobalDirectEnabled(val);
                                setState(() => _globalDirect = val);
                              },
                            ),
                            const SizedBox(height: AelSpacing.sm),
                            Text(
                              '开启后，App 内发起的所有针对校内域名的 HTTP 请求均会强制通过 DIRECT 直连发出，忽略系统配置的常规 HTTP 代理。',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AelSpacing.md),
                      AelSectionCard(
                        title: '为什么开“规则模式”依然打不开？',
                        icon: LucideIcons.circleQuestionMark,
                        child: Text(
                          '1. TUN 虚拟网卡与 Fake-IP 劫持：\n'
                          '手机代理客户端（Clash / Sing-box / NekoBox 等）在开启 VPN 模式时，会通过虚拟网卡拦截所有 IP 数据包。大部分第三方订阅的分流规则未包含浙大校内域名，未匹配的请求会被默认兜底规则（MATCH / FINAL）全量转发至海外节点。\n\n'
                          '2. 浙大防火墙与 WAF 拦截海外机房 IP：\n'
                          '浙大核心系统（统一身份认证、学在浙大、教务系统等）对境外节点实行严格的 WAF 拦截策略。一旦请求经由海外节点发出，将被直接阻断，表现为 403 Forbidden、连接超时或验证码加载失败。',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AelSpacing.md),
                      AelSectionCard(
                        title: '彻底解决：开启“分应用代理”',
                        icon: AelIcons.shield,
                        child: Text(
                          '最有效、最彻底的做法是让代理客户端完全不接管本 App 的流量：\n\n'
                          '• 打开您的代理客户端（如 Clash、Sing-box、NekoBox 或 v2ray）\n'
                          '• 进入【设置】或【路由设置】-> 找到【分应用代理 / 绕过模式】\n'
                          '• 将模式设为【绕过模式】（黑名单模式），勾选【合乐日程 (Helechron)】；或在白名单模式中不要勾选本应用。\n\n'
                          '设置完成后，本 App 的所有数据包将 100% 绕过 VPN 虚拟网卡，直接走本地真实 Wi-Fi / 蜂窝网络，彻底根除所有代理冲突！',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AelSpacing.md),
                      AelSectionCard(
                        title: '规则模式修复：一键复制直连规则',
                        icon: AelIcons.copy,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '如果您不想开启分应用代理，也可以在代理软件中手动添加浙大校内直连分流规则：',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AelSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: AelButton(
                                    variant: AelButtonVariant.tonal,
                                    icon: AelIcons.copy,
                                    label: 'Clash 规则',
                                    onPressed: () => _copyToClipboard(
                                      _clashRules,
                                      '已复制 Clash / Mihomo 规则',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AelSpacing.sm),
                                Expanded(
                                  child: AelButton(
                                    variant: AelButtonVariant.tonal,
                                    icon: AelIcons.copy,
                                    label: 'Sing-box 规则',
                                    onPressed: () => _copyToClipboard(
                                      _singboxRules,
                                      '已复制 Sing-box 规则',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AelSpacing.md),
                      AelSectionCard(
                        title: '校内服务连通性体检',
                        icon: AelIcons.activity,
                        trailing: _isTesting
                            ? const CupertinoActivityIndicator(radius: 8)
                            : AelChip(
                                label: '开始体检',
                                tone: AelChipTone.primary,
                                leadingIcon: AelIcons.refresh,
                                onTap: _runDiagnostics,
                              ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '实时探测当前网络环境下连接浙大各核心业务系统的延迟与状态码：',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AelSpacing.md),
                            ..._targets.map((target) {
                              final res = _diagnosticResults[target.id];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10.0),
                                child: _buildDiagnosticItem(target, res),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticItem(
    _DiagnosticTarget target,
    _DiagnosticItemResult? result,
  ) {
    final colors = AelTheme.colorsOf(context);
    Color statusBg;
    Color statusFg;
    IconData statusIcon;
    String statusTitle;

    if (result == null) {
      statusBg = colors.neutralChipBg;
      statusFg = colors.textTertiary;
      statusIcon = LucideIcons.circle;
      statusTitle = '未体检';
    } else {
      switch (result.state) {
        case _DiagnosticState.testing:
          statusBg = colors.primaryContainer;
          statusFg = colors.onPrimaryContainer;
          statusIcon = AelIcons.refresh;
          statusTitle = '探测中';
          break;
        case _DiagnosticState.success:
          statusBg = colors.successContainer;
          statusFg = colors.onSuccessContainer;
          statusIcon = AelIcons.success;
          statusTitle = '${result.latencyMs}ms';
          break;
        case _DiagnosticState.blocked:
          statusBg = colors.errorContainer;
          statusFg = colors.onErrorContainer;
          statusIcon = LucideIcons.circleX;
          statusTitle = '被拦截(403)';
          break;
        case _DiagnosticState.warning:
          statusBg = colors.warningContainer;
          statusFg = colors.onWarningContainer;
          statusIcon = AelIcons.warning;
          statusTitle = '异常';
          break;
        case _DiagnosticState.error:
          statusBg = colors.errorContainer;
          statusFg = colors.onErrorContainer;
          statusIcon = LucideIcons.circleX;
          statusTitle = '连接超时';
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: colors.tonalTileBg,
        borderRadius: BorderRadius.circular(AelRadius.xs),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result?.message ?? target.description,
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        result?.state == _DiagnosticState.blocked ||
                            result?.state == _DiagnosticState.error
                        ? colors.error
                        : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 11, color: statusFg),
                const SizedBox(width: 3),
                Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusFg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticTarget {
  final String id;
  final String name;
  final String url;
  final String description;

  const _DiagnosticTarget({
    required this.id,
    required this.name,
    required this.url,
    required this.description,
  });
}

enum _DiagnosticState { testing, success, blocked, warning, error }

class _DiagnosticItemResult {
  final _DiagnosticState state;
  final int? latencyMs;
  final int? statusCode;
  final String message;

  _DiagnosticItemResult({
    required this.state,
    this.latencyMs,
    this.statusCode,
    required this.message,
  });
}
