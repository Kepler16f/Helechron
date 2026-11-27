import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/services/diagnostic_log_service.dart';
import 'package:celechron/services/diagnostic_report.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiagnosticLogPage extends StatefulWidget {
  final String version;
  final String buildNumber;
  final String? initialLogText;
  final Future<void> Function()? clearLogs;

  const DiagnosticLogPage({
    required this.version,
    this.buildNumber = '1',
    this.initialLogText,
    this.clearLogs,
    super.key,
  });

  @override
  State<DiagnosticLogPage> createState() => _DiagnosticLogPageState();
}

class _DiagnosticLogPageState extends State<DiagnosticLogPage> {
  final _parser = const DiagnosticReportParser();
  final _expandedReports = <String>{};
  final _expandedIssues = <String>{};
  final _expandedStacks = <String>{};
  late final PageController _pageController;
  String _logText = '';
  DiagnosticReportBundle _bundle = DiagnosticReportBundle.empty;
  int _mode = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.initialLogText != null) {
      _setLogText(widget.initialLogText!);
    } else {
      _reload();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _setLogText(String text) {
    _logText = text;
    _bundle = _parser.parse(text);
    _loading = false;
    final latest = _bundle.latestReport;
    if (latest != null && _expandedReports.isEmpty) {
      _expandedReports.add(latest.refreshId);
    }
  }

  Future<void> _reload() async {
    final text = await DiagnosticLogService.instance.recentText();
    if (!mounted) return;
    setState(() => _setLogText(text));
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _logText));
    if (mounted) await _showMessage('已复制', '完整原始日志已复制到剪贴板。');
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fileName = await DiagnosticLogService.instance.exportAndShare(
        version: widget.version,
        buildNumber: widget.buildNumber,
      );
      if (mounted) await _showMessage('导出成功', '已生成 $fileName');
    } on Object catch (error, stackTrace) {
      DiagnosticLogService.instance.record(
        level: CelechronLogLevel.error,
        module: '诊断日志',
        operation: 'export',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) await _showMessage('导出失败', '无法导出日志：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    await (widget.clearLogs ?? DiagnosticLogService.instance.clear)();
    if (widget.initialLogText == null) {
      await _reload();
    } else if (mounted) {
      setState(() => _setLogText(''));
    }
    if (mounted) await _showMessage('已清空', '测试日志已清空。');
  }

  Future<void> _confirmClear() async {
    final confirmed = await showAelConfirmDialog(
      context: context,
      title: '确定清空测试日志？',
      message: '清空后，当前保存的诊断记录将无法在 App 内恢复。',
      confirmLabel: '清空',
      isDestructive: true,
    );
    if (confirmed && mounted) await _clear();
  }

  Future<void> _showMessage(String title, String message) {
    return showAelAlertDialog(context: context, title: title, message: message);
  }

  void _setMode(int value) {
    if (_mode == value) return;
    setState(() => _mode = value);
    _pageController.animateToPage(
      value,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: AelConstrainedWidth(
          maxWidth: AelBreakpointSpec.maxDetailWidth,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
                child: Row(
                  children: [
                    AelCircleIconButton(
                      icon: AelIcons.back,
                      size: 36,
                      iconSize: 18,
                      tooltip: '返回',
                      onPressed: () {
                        final onBack = AelEmbeddedBackScope.maybeOf(context);
                        if (onBack != null) {
                          onBack();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '诊断与测试',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Semantics(
                  label: '诊断日志显示模式',
                  child: AelSegmented<int>(
                    key: const ValueKey('diagnostic-mode-switch'),
                    stackedIcon: false,
                    value: _mode,
                    items: const [
                      AelSegmentItem(value: 0, label: '易读报告'),
                      AelSegmentItem(value: 1, label: '原始日志'),
                    ],
                    onChanged: _setMode,
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  key: const ValueKey('diagnostic-mode-pages'),
                  controller: _pageController,
                  onPageChanged: (value) => setState(() => _mode = value),
                  children: [
                    _buildReadablePage(context),
                    _buildRawPage(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadablePage(BuildContext context) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (_bundle.reports.isEmpty) {
      return ListView(
        key: const ValueKey('readable-report-page'),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.paddingOf(context).bottom + nativeBottomBarInset() + 16,
        ),
        children: const [
          AelEmptyState(
            icon: LucideIcons.fileSearch,
            title: '暂无可读的刷新记录',
            subtitle: '执行一次刷新后，这里会显示刷新结果、模块状态和关键时间线。',
          ),
        ],
      );
    }
    return CupertinoScrollbar(
      child: ListView(
        key: const ValueKey('readable-report-page'),
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.paddingOf(context).bottom + nativeBottomBarInset() + 16,
        ),
        children: [
          if (_bundle.damagedLineCount > 0)
            _noticeCard(
              context,
              '有 ${_bundle.damagedLineCount} 行日志无法解析，已安全跳过。',
            ),
          if (_bundle.globalTimeline.isNotEmpty)
            _globalTimelineCard(context, _bundle.globalTimeline),
          for (final report in _bundle.reports) ...[
            _reportCard(context, report),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _reportCard(BuildContext context, DiagnosticRefreshReport report) {
    final expanded = _expandedReports.contains(report.refreshId);
    final statusColor = _severityColor(context, report.severity);
    final description = diagnosticReportDescription(report);
    return Semantics(
      container: true,
      label:
          '${diagnosticOriginLabel(report.origin)}，'
          '${diagnosticReportTitle(report)}，'
          '${formatLocalDiagnosticTime(report.startedAtUtc)}',
      child: _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AelIconBadge(
                  icon: _severityIcon(report.severity),
                  size: 38,
                  iconSize: 19,
                  style: AelIconBadgeStyle.cookie,
                  backgroundColor: statusColor.withValues(alpha: 0.14),
                  iconColor: statusColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        diagnosticReportTitle(report),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${diagnosticOriginLabel(report.origin)} · '
                        '${formatLocalDiagnosticTime(report.startedAtUtc)}',
                        style: TextStyle(
                          color: AelTheme.colorsOf(context).textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: TextStyle(color: AelTheme.colorsOf(context).textPrimary),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metric(context, '总耗时', formatDuration(report.durationMs)),
                if (report.performedModuleRequests) ...[
                  _metric(context, '成功', '${report.successCount}'),
                  _metric(context, '降级', '${report.degradedCount}'),
                  _metric(context, '失败', '${report.failedCount}'),
                ],
              ],
            ),
            if (report.performedModuleRequests) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _flag(context, '重新登录', report.relogged),
                  _flag(context, '重试', report.retried),
                  _flag(context, '缓存回退', report.cacheUsed),
                ],
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                key: ValueKey('toggle-report-${report.refreshId}'),
                padding: const EdgeInsets.only(top: 8),
                onPressed: () => setState(() {
                  if (expanded) {
                    _expandedReports.remove(report.refreshId);
                  } else {
                    _expandedReports.add(report.refreshId);
                  }
                }),
                child: Text(
                  expanded ? '收起详情' : '查看详情',
                  style: TextStyle(color: AelTheme.colorsOf(context).primary),
                ),
              ),
            ),
            if (expanded) ...[
              _divider(context),
              if (report.modules.isNotEmpty) ...[
                _sectionTitle(context, '模块状态'),
                for (final module in report.modules)
                  _moduleCard(context, module),
                const SizedBox(height: 10),
              ],
              _sectionTitle(context, '关键时间线'),
              if (report.timeline.isEmpty)
                Text(
                  '没有可展示的关键事件。',
                  style: TextStyle(
                    color: AelTheme.colorsOf(context).textSecondary,
                  ),
                )
              else
                for (final event in report.timeline)
                  _timelineRow(context, event),
              const SizedBox(height: 10),
              _sectionTitle(context, '发现的问题'),
              if (report.issues.isEmpty)
                Text(
                  '未发现需要说明的问题。',
                  style: TextStyle(
                    color: AelTheme.colorsOf(context).textSecondary,
                  ),
                )
              else
                for (final issue in report.issues) _issueCard(context, issue),
            ],
          ],
        ),
      ),
    );
  }

  Widget _moduleCard(BuildContext context, DiagnosticModuleReport module) {
    final colors = AelTheme.colorsOf(context);
    final color = _moduleColor(context, module.state);
    final cacheTime = module.cacheUpdatedAtUtc == null
        ? module.cacheUpdatedText
        : formatLocalDiagnosticTime(module.cacheUpdatedAtUtc!);
    final metaStyle = TextStyle(fontSize: 13, color: colors.textSecondary);
    return Container(
      key: ValueKey('module-${module.name}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.tonalTileBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  module.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                diagnosticModuleStateLabel(module.state),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(module.reason, style: TextStyle(color: colors.textPrimary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(formatModuleDuration(module), style: metaStyle),
              if (module.relogged) Text('已重新登录', style: metaStyle),
              if (module.retried) Text('已重试', style: metaStyle),
              if (cacheTime != null) Text('缓存更新于 $cacheTime', style: metaStyle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(BuildContext context, DiagnosticTimelineEvent event) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(
              LucideIcons.circle,
              size: 8,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: TextStyle(color: colors.textPrimary)),
                Text(
                  '${formatLocalDiagnosticTime(event.timestampUtc)}'
                  '${event.description == null ? '' : ' · ${event.description}'}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _issueCard(BuildContext context, DiagnosticIssue issue) {
    final colors = AelTheme.colorsOf(context);
    final expanded = _expandedIssues.contains(issue.id);
    final stackExpanded = _expandedStacks.contains(issue.id);
    final details = issue.details;
    return Container(
      key: ValueKey('issue-${issue.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: issue.severity == DiagnosticIssueSeverity.error
            ? colors.error.withValues(alpha: 0.08)
            : colors.tonalTileBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            diagnosticIssueCategoryLabel(issue.category),
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            issue.title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(issue.explanation, style: TextStyle(color: colors.textPrimary)),
          CupertinoButton(
            key: ValueKey('toggle-issue-${issue.id}'),
            padding: const EdgeInsets.only(top: 7),
            onPressed: () => setState(() {
              if (expanded) {
                _expandedIssues.remove(issue.id);
              } else {
                _expandedIssues.add(issue.id);
              }
            }),
            child: Text(
              expanded ? '收起技术详情' : '查看技术详情',
              style: TextStyle(color: colors.primary),
            ),
          ),
          if (expanded) ...[
            _technicalRow(context, 'refreshId', details.refreshId),
            _technicalRow(
              context,
              'UTC 时间',
              formatUtcDiagnosticTime(details.timestampUtc),
            ),
            _technicalRow(context, 'HTTP 状态码', '${details.statusCode ?? '-'}'),
            _technicalRow(context, '请求接口', details.interfaceName),
            _technicalRow(context, '已脱敏 URL', details.url ?? '-'),
            _technicalRow(context, '异常类型', details.exceptionType ?? '-'),
            _technicalRow(context, '异常摘要', details.exceptionSummary ?? '-'),
            if (details.stack != null) ...[
              CupertinoButton(
                key: ValueKey('toggle-stack-${issue.id}'),
                padding: const EdgeInsets.only(top: 6),
                onPressed: () => setState(() {
                  if (stackExpanded) {
                    _expandedStacks.remove(issue.id);
                  } else {
                    _expandedStacks.add(issue.id);
                  }
                }),
                child: Text(
                  stackExpanded ? '隐藏堆栈' : '显示堆栈',
                  style: TextStyle(color: colors.primary),
                ),
              ),
              if (stackExpanded)
                Text(
                  details.stack!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _globalTimelineCard(
    BuildContext context,
    List<DiagnosticTimelineEvent> events,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(context, 'App 与后台协调'),
            for (final event in events) _timelineRow(context, event),
          ],
        ),
      ),
    );
  }

  Widget _buildRawPage(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final displayText = _loading
        ? '正在读取日志…'
        : _logText.isEmpty
        ? '暂无诊断日志。执行一次刷新后再试。'
        : _logText;
    return CupertinoScrollbar(
      child: ListView(
        key: const ValueKey('raw-log-page'),
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.paddingOf(context).bottom + nativeBottomBarInset() + 16,
        ),
        children: [
          AelSectionCard(
            title: '完整原始日志',
            icon: AelIcons.file,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AelListRow(
                  icon: AelIcons.copy,
                  iconBgColor: colors.primaryContainer,
                  iconColor: colors.onPrimaryContainer,
                  title: '复制完整原始日志',
                  onTap: _copy,
                ),
                const SizedBox(height: AelSpacing.sm),
                AelListRow(
                  icon: AelIcons.share,
                  iconBgColor: colors.infoContainer,
                  iconColor: colors.onInfoContainer,
                  title: _busy ? '正在导出…' : '导出并分享 TXT',
                  subtitle: '包含易读报告和完整原始日志',
                  onTap: _busy ? null : _export,
                ),
                const SizedBox(height: AelSpacing.sm),
                AelListRow(
                  icon: AelIcons.delete,
                  iconBgColor: colors.errorContainer,
                  iconColor: colors.onErrorContainer,
                  title: '清空测试日志',
                  showChevron: false,
                  onTap: _confirmClear,
                ),
                const SizedBox(height: AelSpacing.sm),
                Text(
                  '原始日志继续使用 UTC 时间并保留完整脱敏技术字段；最多保留 2000 行和最近 10 个导出文件。',
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AelSectionCard(
            padding: const EdgeInsets.all(12),
            child: Text(
              displayText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.35,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    final colors = AelTheme.colorsOf(context);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.cardBg,
        shape: AelShapes.squircle(AelRadius.card),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }

  Widget _noticeCard(BuildContext context, String text) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _card(
        context,
        child: Row(
          children: [
            Icon(AelIcons.info, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: TextStyle(color: colors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    final colors = AelTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.tonalTileBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
      ),
    );
  }

  Widget _flag(BuildContext context, String label, bool enabled) {
    final colors = AelTheme.colorsOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          enabled ? AelIcons.success : LucideIcons.circleMinus,
          size: 15,
          color: enabled ? colors.success : colors.textTertiary,
        ),
        const SizedBox(width: 4),
        Text(
          '$label ${enabled ? '是' : '否'}',
          style: TextStyle(
            color: enabled ? colors.textPrimary : colors.textSecondary,
            fontSize: 13.5,
          ),
        ),
      ],
    );
  }

  Widget _technicalRow(BuildContext context, String label, String value) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        '$label：$value',
        style: TextStyle(color: colors.textSecondary, fontSize: 13),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.only(bottom: 14),
      color: AelTheme.colorsOf(context).divider,
    );
  }

  Color _severityColor(
    BuildContext context,
    DiagnosticReportSeverity severity,
  ) {
    final colors = AelTheme.colorsOf(context);
    return switch (severity) {
      DiagnosticReportSeverity.success => colors.success,
      DiagnosticReportSeverity.degraded => colors.warning,
      DiagnosticReportSeverity.failed => colors.error,
      DiagnosticReportSeverity.incomplete => colors.warning,
      DiagnosticReportSeverity.coordinated => colors.primary,
    };
  }

  IconData _severityIcon(DiagnosticReportSeverity severity) {
    return switch (severity) {
      DiagnosticReportSeverity.success => AelIcons.success,
      DiagnosticReportSeverity.degraded => AelIcons.warning,
      DiagnosticReportSeverity.failed => LucideIcons.circleX,
      DiagnosticReportSeverity.incomplete => LucideIcons.circleQuestionMark,
      DiagnosticReportSeverity.coordinated => AelIcons.refresh,
    };
  }

  Color _moduleColor(BuildContext context, DiagnosticModuleState state) {
    final colors = AelTheme.colorsOf(context);
    return switch (state) {
      DiagnosticModuleState.liveSuccess => colors.success,
      DiagnosticModuleState.cache => colors.warning,
      DiagnosticModuleState.failed => colors.error,
      DiagnosticModuleState.notExecuted => colors.textSecondary,
    };
  }
}
