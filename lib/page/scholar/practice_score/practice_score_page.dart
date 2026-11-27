import 'package:flutter/cupertino.dart'
    show
        CupertinoPageScaffold,
        CupertinoPageRoute,
        CupertinoTextField,
        OverlayVisibilityMode;
import 'package:flutter/material.dart' show Divider;
import 'package:flutter/widgets.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/practice_score_item.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/utils/practice_target_helper.dart';

class PracticeScoreColumns extends StatelessWidget {
  final Scholar scholar;

  const PracticeScoreColumns({super.key, required this.scholar});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    void open(int categoryId) {
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => PracticeScorePage(
            scholar: scholar,
            initialCategoryId: categoryId,
          ),
        ),
      );
    }

    final passed = <String>[
      if (scholar.practiceMyPassed != null)
        '美育：${scholar.practiceMyPassed! ? '已通过' : '未通过'}',
      if (scholar.practiceLyPassed != null)
        '劳育：${scholar.practiceLyPassed! ? '已通过' : '未通过'}',
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: AelStatTile(
                key: const ValueKey('practice-score-category-1'),
                label: '二课记点',
                value: scholar.pt2.toStringAsFixed(2),
                onTap: () => open(1),
              ),
            ),
            const SizedBox(width: AelSpacing.sm),
            Expanded(
              child: AelStatTile(
                key: const ValueKey('practice-score-category-2'),
                label: '三课记点',
                value: scholar.pt3.toStringAsFixed(2),
                onTap: () => open(2),
              ),
            ),
            const SizedBox(width: AelSpacing.sm),
            Expanded(
              child: AelStatTile(
                key: const ValueKey('practice-score-category-3'),
                label: '四课记点',
                value: scholar.pt4.toStringAsFixed(2),
                onTap: () => open(3),
              ),
            ),
          ],
        ),
        if (passed.isNotEmpty) ...[
          const SizedBox(height: AelSpacing.sm),
          Text(
            passed.join(' · '),
            key: const ValueKey('practice-passed-status'),
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: AelSpacing.sm),
        AelListRow(
          title: '素拓看板',
          subtitle: '查看二三四课堂实践记点详情',
          icon: AelIcons.sparkles,
          iconBgColor: colors.primaryContainer,
          iconColor: colors.onPrimaryContainer,
          onTap: () => open(0),
        ),
      ],
    );
  }
}

class PracticeScorePage extends StatefulWidget {
  final Scholar scholar;
  final int initialCategoryId;

  const PracticeScorePage({
    super.key,
    required this.scholar,
    this.initialCategoryId = 1,
  });

  @override
  State<PracticeScorePage> createState() => _PracticeScorePageState();
}

class _PracticeScorePageState extends State<PracticeScorePage> {
  late int _selectedCategoryId;
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
  }

  String _getCategoryTitle(int catId) => switch (catId) {
    0 => '全部看板',
    1 => '第二课堂',
    2 => '第三课堂',
    3 => '第四课堂',
    _ => '素拓课堂',
  };

  double _getCategoryScore(int catId) => switch (catId) {
    1 => widget.scholar.pt2,
    2 => widget.scholar.pt3,
    3 => widget.scholar.pt4,
    _ => widget.scholar.pt2 + widget.scholar.pt3 + widget.scholar.pt4,
  };

  void _showSetTargetDialog(int catId) {
    final currentTarget = PracticeTargetHelper.getTarget(catId);
    final textController = TextEditingController(
      text: currentTarget > 0 ? currentTarget.toStringAsFixed(2) : '',
    );

    showAelDialog<void>(
      context: context,
      title: '设置${_getCategoryTitle(catId)}目标记点',
      content: Builder(
        builder: (ctx) {
          final colors = AelTheme.colorsOf(ctx);
          return CupertinoTextField(
            controller: textController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: '如: 4.0',
            autofocus: true,
            clearButtonMode: OverlayVisibilityMode.editing,
            padding: const EdgeInsets.symmetric(
              horizontal: AelSpacing.md,
              vertical: AelSpacing.md,
            ),
            style: TextStyle(color: colors.textPrimary, fontSize: 15),
            placeholderStyle: TextStyle(color: colors.textTertiary),
            decoration: BoxDecoration(
              color: colors.tonalTileBg,
              borderRadius: BorderRadius.circular(AelRadius.tile),
            ),
          );
        },
      ),
      actions: [
        const AelDialogAction<void>(
          label: '取消',
          variant: AelButtonVariant.tonal,
        ),
        AelDialogAction<void>(
          label: '清除目标',
          isDestructive: true,
          onPressed: () async {
            await PracticeTargetHelper.setTarget(catId, 0.0);
            if (mounted) setState(() {});
          },
        ),
        AelDialogAction<void>(
          label: '保存',
          variant: AelButtonVariant.primary,
          onPressed: () async {
            final val = double.tryParse(textController.text.trim()) ?? 0.0;
            await PracticeTargetHelper.setTarget(catId, val);
            if (mounted) setState(() {});
          },
        ),
      ],
    ).then((_) => textController.dispose());
  }

  Widget _buildCategorySegment() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AelSegmented<int>(
        value: _selectedCategoryId,
        stackedIcon: false,
        onChanged: (val) => setState(() => _selectedCategoryId = val),
        items: const [
          AelSegmentItem(value: 0, label: '总览'),
          AelSegmentItem(value: 1, label: '二课'),
          AelSegmentItem(value: 2, label: '三课'),
          AelSegmentItem(value: 3, label: '四课'),
        ],
      ),
    );
  }

  Widget _buildTargetCard(int catId) {
    final colors = AelTheme.colorsOf(context);
    final current = _getCategoryScore(catId);
    final target = PracticeTargetHelper.getTarget(catId);
    final hasTarget = target > 0;
    final isPassed = hasTarget && current >= target;
    final progress = hasTarget ? (current / target).clamp(0.0, 1.0) : 0.0;

    return AelSectionCard(
      padding: const EdgeInsets.all(16),
      cornerRadius: AelRadius.tile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_getCategoryTitle(catId)}目标',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: colors.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () => _showSetTargetDialog(catId),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasTarget ? '修改目标' : '设置目标',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      AelIcons.chevronRight,
                      size: 13,
                      color: colors.primary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '当前 ${current.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              if (hasTarget) ...[
                Text(
                  ' / ${target.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 16, color: colors.textSecondary),
                ),
              ],
              const Spacer(),
              AelChip(
                label: !hasTarget
                    ? '无目标'
                    : (isPassed
                          ? '已达标'
                          : '未达标(差${(target - current).toStringAsFixed(2)})'),
                tone: !hasTarget
                    ? AelChipTone.neutral
                    : (isPassed ? AelChipTone.success : AelChipTone.warning),
              ),
            ],
          ),
          if (hasTarget) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 6,
                color: colors.tonalTileBg,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    color: isPassed ? colors.success : colors.warning,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQualityBreakdown(List<PracticeScoreItem> items) {
    final colors = AelTheme.colorsOf(context);
    final breakdown = <String, double>{};
    for (final item in items) {
      if (item.countsTowardTotal) {
        final key = item.qualityType.isNotEmpty ? item.qualityType : '未分类';
        breakdown[key] = (breakdown[key] ?? 0.0) + item.score;
      }
    }
    if (breakdown.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AelSectionCard(
        padding: const EdgeInsets.all(16),
        cornerRadius: AelRadius.tile,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '素质类型记点统计',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: breakdown.entries.map((entry) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.tonalTileBg,
                    borderRadius: BorderRadius.circular(AelRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        entry.value.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final allItems = widget.scholar.practiceScoreItems;
    final filteredItems = _selectedCategoryId == 0
        ? List<PracticeScoreItem>.from(allItems)
        : allItems.where((i) => i.categoryId == _selectedCategoryId).toList();

    filteredItems.sort((a, b) {
      final dateA = _sortDate(a);
      final dateB = _sortDate(b);
      return _sortAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
    });

    final included = filteredItems
        .where((item) => item.countsTowardTotal)
        .toList(growable: false);
    final inReview = filteredItems
        .where(
          (item) =>
              !item.countsTowardTotal &&
              (item.statusValue == 2 || item.statusLabel == '审核中'),
        )
        .toList(growable: false);
    final otherExcluded = filteredItems
        .where(
          (item) =>
              !item.countsTowardTotal &&
              item.statusValue != 2 &&
              item.statusLabel != '审核中',
        )
        .toList(growable: false);

    final summaryWidgets = <Widget>[
      _buildCategorySegment(),
      if (_selectedCategoryId == 0) ...[
        _buildTargetCard(1),
        const SizedBox(height: 10),
        _buildTargetCard(2),
        const SizedBox(height: 10),
        _buildTargetCard(3),
      ] else ...[
        _buildTargetCard(_selectedCategoryId),
      ],
      const SizedBox(height: 12),
      _SummaryCard(
        categoryName: _selectedCategoryId == 0
            ? '全部看板'
            : '${_getCategoryTitle(_selectedCategoryId)}项目',
        total: _getCategoryScore(_selectedCategoryId),
        includedCount: included.length,
        excludedCount: inReview.length + otherExcluded.length,
        source: widget.scholar.practiceSummarySource,
        detailSource: widget.scholar.practiceDataSource,
        updatedAt: widget.scholar.practiceUpdatedAt,
        stale: widget.scholar.practiceSummaryStale,
        detailsStale: widget.scholar.practiceDetailsStale,
      ),
      _buildQualityBreakdown(filteredItems),
    ];

    final projectWidgets = <Widget>[
      if (!widget.scholar.practiceDetailsAvailable)
        _NoDetailsCard(source: widget.scholar.practiceDataSource)
      else ...[
        _SectionTitle(title: '已计入记点项目', count: included.length),
        if (included.isEmpty)
          const _EmptyGroup(text: '暂无已计入记点的项目')
        else
          ...included.map(
            (item) => _PracticeItemCard(
              item: item,
              onTap: () => _openDetail(context, item),
            ),
          ),
        const SizedBox(height: 12),
        if (inReview.isNotEmpty) ...[
          _SectionTitle(title: '审核中项目', count: inReview.length),
          ...inReview.map(
            (item) => _PracticeItemCard(
              item: item,
              onTap: () => _openDetail(context, item),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _SectionTitle(title: '未计入或其他项目', count: otherExcluded.length),
        if (otherExcluded.isEmpty && inReview.isEmpty)
          const _EmptyGroup(text: '暂无未计入或异常项目')
        else if (otherExcluded.isNotEmpty)
          ...otherExcluded.map(
            (item) => _PracticeItemCard(
              item: item,
              onTap: () => _openDetail(context, item),
            ),
          ),
      ],
    ];

    final bottomPad =
        MediaQuery.paddingOf(context).bottom + nativeBottomBarInset() + 16;

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (AelResponsive.isWideBody(constraints.maxWidth)) {
            return SafeArea(
              bottom: false,
              child: AelConstrainedWidth(
                maxWidth: AelBreakpointSpec.maxWideContentWidth,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Row(
                        children: [
                          AelCircleIconButton(
                            icon: AelIcons.back,
                            size: 36,
                            iconSize: 18,
                            tooltip: '返回',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_getCategoryTitle(_selectedCategoryId)}看板',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          AelChip(
                            label: _sortAscending ? '正序' : '倒序',
                            leadingIcon: AelIcons.filter,
                            tone: AelChipTone.primary,
                            onTap: () => setState(
                              () => _sortAscending = !_sortAscending,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: AelTwoPane(
                        masterFraction: 0.42,
                        minMasterWidth: 320,
                        maxMasterWidth: 460,
                        master: ListView(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
                          children: summaryWidgets,
                        ),
                        detail: ListView(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
                          children: projectWidgets,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              CelechronSliverTextHeader(
                subtitle: '${_getCategoryTitle(_selectedCategoryId)}看板',
                right: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: AelChip(
                    label: _sortAscending ? '正序' : '倒序',
                    leadingIcon: AelIcons.filter,
                    tone: AelChipTone.primary,
                    onTap: () =>
                        setState(() => _sortAscending = !_sortAscending),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
                sliver: SliverToBoxAdapter(
                  child: AelConstrainedWidth(
                    maxWidth: AelBreakpointSpec.maxDetailWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...summaryWidgets,
                        const SizedBox(height: 16),
                        ...projectWidgets,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, PracticeScoreItem item) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PracticeScoreDetailPage(item: item),
      ),
    );
  }

  static DateTime _sortDate(PracticeScoreItem item) =>
      item.updatedAt ?? item.activityStart ?? DateTime(1970);
}

class PracticeScoreDetailPage extends StatelessWidget {
  final PracticeScoreItem item;

  const PracticeScoreDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final rows = <(String, String)>[
      ('项目名称', item.projectName),
      ('获得记点', _score(item)),
      ('课堂类别', item.categoryName),
      ('审核状态', item.statusLabel),
      ('项目类别', item.projectType),
      ('素质类别', item.qualityType),
      ('参与身份或得分原因', item.role ?? '未填写'),
      ('情况说明', item.remark ?? '未填写'),
      ('活动开始时间', _dateTime(item.activityStart)),
      ('活动结束时间', _dateTime(item.activityEnd)),
      ('最近更新时间', _dateTime(item.updatedAt)),
    ];
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: CustomScrollView(
        slivers: [
          const CelechronSliverTextHeader(subtitle: '实践项目详情'),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom +
                  nativeBottomBarInset() +
                  16,
            ),
            sliver: SliverToBoxAdapter(
              child: AelConstrainedWidth(
                maxWidth: AelBreakpointSpec.maxDetailWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AelSectionCard(
                      padding: const EdgeInsets.all(16),
                      cornerRadius: AelRadius.tile,
                      child: Column(
                        children: [
                          for (var index = 0; index < rows.length; index++) ...[
                            _DetailRow(
                              label: rows[index].$1,
                              value: rows[index].$2,
                            ),
                            if (index != rows.length - 1)
                              Divider(height: 1, color: colors.divider),
                          ],
                        ],
                      ),
                    ),
                    if (!item.countsTowardTotal) ...[
                      const SizedBox(height: 12),
                      Text(
                        '该项目当前未计入总分。',
                        style: TextStyle(color: colors.warning, fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String categoryName;
  final double total;
  final int includedCount;
  final int excludedCount;
  final PracticeSummarySource source;
  final PracticeDataSource detailSource;
  final DateTime? updatedAt;
  final bool stale;
  final bool detailsStale;

  const _SummaryCard({
    required this.categoryName,
    required this.total,
    required this.includedCount,
    required this.excludedCount,
    required this.source,
    required this.detailSource,
    required this.updatedAt,
    required this.stale,
    required this.detailsStale,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return AelSectionCard(
      padding: const EdgeInsets.all(16),
      cornerRadius: AelRadius.tile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            categoryName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '正式汇总记点',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            total.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已计入 $includedCount 项 · 审核中/未计入 $excludedCount 项',
            style: TextStyle(fontSize: 13, color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '记点来源：${source.label}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '项目明细来源：${detailSource.label}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '更新时间：${_dateTime(updatedAt)}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          if (stale) ...[
            const SizedBox(height: 8),
            Text(
              '当前记点使用缓存或项目合计，请在网络恢复后刷新。',
              style: TextStyle(color: colors.warning, fontSize: 12),
            ),
          ],
          if (detailsStale) ...[
            const SizedBox(height: 4),
            Text(
              '项目明细为缓存或上一次结果。',
              style: TextStyle(color: colors.warning, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoDetailsCard extends StatelessWidget {
  final PracticeDataSource source;

  const _NoDetailsCard({required this.source});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final zdbkOnly =
        source == PracticeDataSource.zdbkLive ||
        source == PracticeDataSource.zdbkCache;
    return AelSectionCard(
      padding: const EdgeInsets.all(16),
      cornerRadius: AelRadius.tile,
      child: Text(
        zdbkOnly ? '当前仅获取到旧实践汇总，暂无 getSqjl 项目明细。' : '当前 getSqjl 项目明细不可用，请稍后刷新。',
        key: const ValueKey('practice-no-details'),
        style: TextStyle(color: colors.textSecondary, height: 1.5),
      ),
    );
  }
}

class _PracticeItemCard extends StatelessWidget {
  final PracticeScoreItem item;
  final VoidCallback onTap;

  const _PracticeItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final counted = item.countsTowardTotal;
    final isInReview =
        !counted && (item.statusValue == 2 || item.statusLabel == '审核中');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AelSectionCard(
        key: ValueKey('practice-item-${item.id}'),
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        cornerRadius: AelRadius.tile,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.projectName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    counted
                        ? item.statusLabel
                        : (isInReview
                              ? '${item.statusLabel}（审核中）'
                              : '${item.statusLabel} · 未计入总分'),
                    style: TextStyle(
                      color: counted
                          ? colors.success
                          : (isInReview
                                ? colors.warning
                                : colors.textSecondary),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.projectType} · ${item.qualityType}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '更新于 ${_dateTime(item.updatedAt)}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${counted ? '+' : ''}${_score(item)}',
              style: TextStyle(
                color: counted ? colors.success : colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Icon(AelIcons.chevronRight, size: 14, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Text(
        '$title（$count）',
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyGroup extends StatelessWidget {
  final String text;

  const _EmptyGroup({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
      child: Text(text, style: TextStyle(color: colors.textSecondary)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: TextStyle(color: colors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

String _score(PracticeScoreItem item) => item.score.isFinite && item.score >= 0
    ? item.score.toStringAsFixed(2)
    : '—';

String _dateTime(DateTime? value) {
  if (value == null) return '未知';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
