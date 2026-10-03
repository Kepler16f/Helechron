import 'package:celechron/design/multiple_columns.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/model/practice_score_item.dart';
import 'package:celechron/model/scholar.dart';
import 'package:celechron/utils/practice_target_helper.dart';
import 'package:flutter/cupertino.dart';

class PracticeScoreColumns extends StatelessWidget {
  final Scholar scholar;

  const PracticeScoreColumns({super.key, required this.scholar});

  @override
  Widget build(BuildContext context) {
    Widget score(int categoryId, double value) => Text(
          value.toStringAsFixed(2),
          key: ValueKey('practice-score-category-$categoryId'),
          style: CupertinoTheme.of(context)
              .textTheme
              .navTitleTextStyle
              .copyWith(fontSize: 18, fontWeight: FontWeight.bold),
        );

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
        MultipleColumns(
          contents: [
            score(1, scholar.pt2),
            score(2, scholar.pt3),
            score(3, scholar.pt4),
          ],
          titles: const ['二课记点', '三课记点', '四课记点'],
          onTaps: [
            () => open(1),
            () => open(2),
            () => open(3),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (passed.isNotEmpty)
              Text(
                passed.join(' · '),
                key: const ValueKey('practice-passed-status'),
                style: const TextStyle(
                  color: CupertinoColors.secondaryLabel,
                  fontSize: 13,
                ),
              ),
            if (passed.isNotEmpty) const SizedBox(width: 12),
            GestureDetector(
              onTap: () => open(0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '素拓看板',
                    style: TextStyle(
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    size: 13,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
                ],
              ),
            ),
          ],
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

    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('设置${_getCategoryTitle(catId)}目标记点'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: textController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: '如: 4.0',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              final nav = Navigator.of(ctx);
              await PracticeTargetHelper.setTarget(catId, 0.0);
              if (mounted) setState(() {});
              nav.pop();
            },
            child: const Text('清除目标'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final val = double.tryParse(textController.text.trim()) ?? 0.0;
              await PracticeTargetHelper.setTarget(catId, val);
              if (mounted) setState(() {});
              nav.pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySegment() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: _selectedCategoryId,
        children: const {
          0: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('总览', style: TextStyle(fontSize: 13)),
          ),
          1: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('二课', style: TextStyle(fontSize: 13)),
          ),
          2: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('三课', style: TextStyle(fontSize: 13)),
          ),
          3: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('四课', style: TextStyle(fontSize: 13)),
          ),
        },
        onValueChanged: (val) {
          if (val != null) setState(() => _selectedCategoryId = val);
        },
      ),
    );
  }

  Widget _buildTargetCard(int catId) {
    final current = _getCategoryScore(catId);
    final target = PracticeTargetHelper.getTarget(catId);
    final hasTarget = target > 0;
    final isPassed = hasTarget && current >= target;
    final progress = hasTarget ? (current / target).clamp(0.0, 1.0) : 0.0;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_getCategoryTitle(catId)}目标',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _showSetTargetDialog(catId),
                child: Row(
                  children: [
                    Text(
                      hasTarget ? '修改目标' : '设置目标',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const Icon(CupertinoIcons.chevron_forward, size: 13),
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
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (hasTarget) ...[
                Text(
                  ' / ${target.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (!hasTarget
                          ? CupertinoColors.inactiveGray
                          : (isPassed
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemOrange))
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  !hasTarget
                      ? '无目标'
                      : (isPassed
                          ? '已达标'
                          : '未达标 (差 ${(target - current).toStringAsFixed(2)})'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: (!hasTarget
                            ? CupertinoColors.secondaryLabel
                            : (isPassed
                                ? CupertinoColors.systemGreen
                                : CupertinoColors.systemOrange))
                        .resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
          if (hasTarget) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 6,
                color: CupertinoColors.systemFill.resolveFrom(context),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    color: isPassed
                        ? CupertinoColors.systemGreen.resolveFrom(context)
                        : CupertinoColors.systemOrange.resolveFrom(context),
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
      child: _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '素质类型记点统计',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: breakdown.entries.map((entry) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemFill.resolveFrom(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        entry.value.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color:
                              CupertinoColors.activeBlue.resolveFrom(context),
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
        .where((item) =>
            !item.countsTowardTotal &&
            (item.statusValue == 2 || item.statusLabel.contains('审核')))
        .toList(growable: false);
    final otherExcluded = filteredItems
        .where((item) =>
            !item.countsTowardTotal &&
            (item.statusValue != 2 && !item.statusLabel.contains('审核')))
        .toList(growable: false);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('${_getCategoryTitle(_selectedCategoryId)}看板'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () {
            setState(() => _sortAscending = !_sortAscending);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _sortAscending
                    ? CupertinoIcons.sort_up
                    : CupertinoIcons.sort_down,
                size: 16,
              ),
              const SizedBox(width: 2),
              Text(
                _sortAscending ? '正序' : '倒序',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      ),
      backgroundColor: CupertinoDynamicColor.resolve(
        CupertinoColors.systemGroupedBackground,
        context,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.paddingOf(context).bottom +
                  nativeBottomBarInset() +
                  16),
          children: [
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
              categoryName: _getCategoryTitle(_selectedCategoryId),
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
            const SizedBox(height: 16),
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
          ],
        ),
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
      navigationBar: const CupertinoNavigationBar(middle: Text('实践项目详情')),
      backgroundColor: CupertinoDynamicColor.resolve(
        CupertinoColors.systemGroupedBackground,
        context,
      ),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.paddingOf(context).bottom +
                  nativeBottomBarInset() +
                  16),
          children: [
            _Card(
              child: Column(
                children: [
                  for (var index = 0; index < rows.length; index++) ...[
                    _DetailRow(label: rows[index].$1, value: rows[index].$2),
                    if (index != rows.length - 1) const _Divider(),
                  ],
                ],
              ),
            ),
            if (!item.countsTowardTotal) ...[
              const SizedBox(height: 12),
              const Text(
                '该项目当前未计入总分。',
                style: TextStyle(
                  color: CupertinoColors.systemOrange,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
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
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            categoryName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            '正式汇总记点',
            style:
                TextStyle(color: CupertinoColors.secondaryLabel, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            total.toStringAsFixed(2),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '已计入 $includedCount 项 · 审核中/未计入 $excludedCount 项',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '记点来源：${source.label}',
            style: const TextStyle(
                color: CupertinoColors.secondaryLabel, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '项目明细来源：${detailSource.label}',
            style: const TextStyle(
                color: CupertinoColors.secondaryLabel, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            '更新时间：${_dateTime(updatedAt)}',
            style: const TextStyle(
                color: CupertinoColors.secondaryLabel, fontSize: 12),
          ),
          if (stale) ...[
            const SizedBox(height: 8),
            const Text(
              '当前记点使用缓存或项目合计，请在网络恢复后刷新。',
              style:
                  TextStyle(color: CupertinoColors.systemOrange, fontSize: 12),
            ),
          ],
          if (detailsStale) ...[
            const SizedBox(height: 4),
            const Text(
              '项目明细为缓存或上一次结果。',
              style:
                  TextStyle(color: CupertinoColors.systemOrange, fontSize: 12),
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
    final zdbkOnly = source == PracticeDataSource.zdbkLive ||
        source == PracticeDataSource.zdbkCache;
    return _Card(
      child: Text(
        zdbkOnly ? '当前仅获取到旧实践汇总，暂无 getSqjl 项目明细。' : '当前 getSqjl 项目明细不可用，请稍后刷新。',
        key: const ValueKey('practice-no-details'),
        style: const TextStyle(
          color: CupertinoColors.secondaryLabel,
          height: 1.5,
        ),
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
    final counted = item.countsTowardTotal;
    final isInReview =
        !counted && (item.statusValue == 2 || item.statusLabel.contains('审核'));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CupertinoButton(
        key: ValueKey('practice-item-${item.id}'),
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.projectName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
                            ? CupertinoColors.systemGreen
                            : (isInReview
                                ? CupertinoColors.systemOrange
                                : CupertinoColors.secondaryLabel),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.projectType} · ${item.qualityType}',
                      style: const TextStyle(
                        color: CupertinoColors.secondaryLabel,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '更新于 ${_dateTime(item.updatedAt)}',
                      style: const TextStyle(
                        color: CupertinoColors.tertiaryLabel,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${counted ? '+' : ''}${_score(item)}',
                style: TextStyle(
                  color: counted
                      ? CupertinoColors.systemGreen
                      : CupertinoColors.label,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                CupertinoIcons.chevron_forward,
                size: 14,
                color: CupertinoColors.tertiaryLabel,
              ),
            ],
          ),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Text(
          '$title（$count）',
          style: const TextStyle(
            color: CupertinoColors.secondaryLabel,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _EmptyGroup extends StatelessWidget {
  final String text;

  const _EmptyGroup({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
        child: Text(
          text,
          style: const TextStyle(color: CupertinoColors.secondaryLabel),
        ),
      );
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground,
            context,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.label,
              context,
            ),
            fontSize: 15,
          ),
          child: child,
        ),
      );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(color: CupertinoColors.secondaryLabel),
              ),
            ),
            Expanded(
              child: Text(value, textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        height: 0.5,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.separator,
          context,
        ),
      );
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
