import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

/// 响应式窗口宽度分档。
enum AelWindowSizeClass { compact, medium, expanded, large }

/// 统一响应式断点工具（以当前窗口宽度为准，兼容平板旋转、分屏、悬浮窗与折叠屏）。
final class AelResponsive {
  const AelResponsive._();

  static AelWindowSizeClass sizeClassForWidth(double width) {
    if (width >= AelBreakpointSpec.largeMinWidth) {
      return AelWindowSizeClass.large;
    }
    if (width >= AelBreakpointSpec.expandedMinWidth) {
      return AelWindowSizeClass.expanded;
    }
    if (width >= AelBreakpointSpec.mediumMinWidth) {
      return AelWindowSizeClass.medium;
    }
    return AelWindowSizeClass.compact;
  }

  static AelWindowSizeClass sizeClassOf(BuildContext context) {
    return sizeClassForWidth(MediaQuery.sizeOf(context).width);
  }

  /// 是否使用左侧垂直导航栏替代底部导航栏。
  static bool useSideRail(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= AelTabBarSpec.sideRailBreakpoint;
  }

  /// 是否具备足够的正文宽度来启用双栏（如左列表/右详情、左日历/右日程）。
  static bool isWideBody(double bodyWidth) {
    return bodyWidth >= AelBreakpointSpec.bodyTwoPaneMinWidth;
  }

  /// 根据可用内容宽度计算自适应网格列数。
  static int gridColumnsForWidth(
    double width, {
    int maxColumns = 3,
    double minItemWidth = 310,
  }) {
    if (width < AelBreakpointSpec.bodyTwoPaneMinWidth - 80) return 1;
    final raw = (width / minItemWidth).floor();
    return raw.clamp(1, maxColumns);
  }
}

/// 在宽屏下限制子组件最大宽度并水平居中，保持舒适阅读宽度。
class AelConstrainedWidth extends StatelessWidget {
  const AelConstrainedWidth({
    super.key,
    required this.child,
    this.maxWidth = AelBreakpointSpec.maxDetailWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// 等宽自适应多行卡片网格（不强制固定宽高比，允许卡片按内容自然伸展）。
class AelAdaptiveGrid extends StatelessWidget {
  const AelAdaptiveGrid({
    super.key,
    required this.children,
    this.maxColumns = 3,
    this.minItemWidth = 310,
    this.horizontalGap = AelSpacing.sectionGap,
    this.verticalGap = AelSpacing.sectionGap,
  });

  final List<Widget> children;
  final int maxColumns;
  final double minItemWidth;
  final double horizontalGap;
  final double verticalGap;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = AelResponsive.gridColumnsForWidth(
          constraints.maxWidth,
          maxColumns: maxColumns,
          minItemWidth: minItemWidth,
        );
        if (cols <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: verticalGap),
                children[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (int start = 0; start < children.length; start += cols) {
          final end = math.min(start + cols, children.length);
          final rowItems = <Widget>[];
          for (int col = 0; col < cols; col++) {
            if (col > 0) rowItems.add(SizedBox(width: horizontalGap));
            final idx = start + col;
            if (idx < end) {
              rowItems.add(Expanded(child: children[idx]));
            } else {
              rowItems.add(const Expanded(child: SizedBox.shrink()));
            }
          }
          if (rows.isNotEmpty) rows.add(SizedBox(height: verticalGap));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rowItems,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

/// 瀑布流多列布局：在宽屏 / 平板横屏下按列累加堆叠子项，消除不等高卡片造成的行对齐留白；
/// 窄屏自动退化为单列 [Column]。
class AelMasonryGrid extends StatelessWidget {
  const AelMasonryGrid({
    super.key,
    required this.children,
    this.maxColumns = 2,
    this.minItemWidth = 360,
    this.horizontalGap = AelSpacing.md,
    this.verticalGap = AelSpacing.sectionGap,
    this.itemWeights,
  });

  final List<Widget> children;
  final int maxColumns;
  final double minItemWidth;
  final double horizontalGap;
  final double verticalGap;

  /// 可选预估高度权重（与 [children] 一一对应），用于贪心分配到当前最短列以保持左右平衡。
  final List<double>? itemWeights;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = AelResponsive.gridColumnsForWidth(
          constraints.maxWidth,
          maxColumns: maxColumns,
          minItemWidth: minItemWidth,
        );
        if (cols <= 1 || children.length <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: verticalGap),
                children[i],
              ],
            ],
          );
        }

        final colItems = List.generate(cols, (_) => <Widget>[]);
        final colHeights = List<double>.filled(cols, 0);
        for (var i = 0; i < children.length; i++) {
          var targetCol = 0;
          for (var c = 1; c < cols; c++) {
            if (colHeights[c] < colHeights[targetCol]) {
              targetCol = c;
            }
          }
          if (colItems[targetCol].isNotEmpty) {
            colItems[targetCol].add(SizedBox(height: verticalGap));
          }
          colItems[targetCol].add(children[i]);
          final weight =
              (itemWeights != null &&
                  i < itemWeights!.length &&
                  itemWeights![i] > 0)
              ? itemWeights![i]
              : 1.0;
          colHeights[targetCol] += weight;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) SizedBox(width: horizontalGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: colItems[c],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 通用列表-详情双栏容器：宽屏左/右并排，窄屏仅渲染主内容（或调用 fallback）。
class AelTwoPane extends StatelessWidget {
  const AelTwoPane({
    super.key,
    required this.master,
    required this.detail,
    this.masterFraction = 0.40,
    this.minMasterWidth = 300,
    this.maxMasterWidth = 440,
    this.minWidthForTwoPane = AelBreakpointSpec.bodyTwoPaneMinWidth,
    this.showDivider = true,
  });

  final Widget master;
  final Widget detail;
  final double masterFraction;
  final double minMasterWidth;
  final double maxMasterWidth;
  final double minWidthForTwoPane;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidthForTwoPane) {
          return master;
        }
        final masterWidth = (constraints.maxWidth * masterFraction).clamp(
          minMasterWidth,
          maxMasterWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: masterWidth, child: master),
            if (showDivider)
              Container(
                width: 0.5,
                color: colors.divider.withValues(alpha: 0.55),
              ),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

/// 为平板双栏右侧内嵌子页面提供返回上级的语义作用域，替代整页路由出栈。
class AelEmbeddedBackScope extends InheritedWidget {
  const AelEmbeddedBackScope({
    super.key,
    required this.onBack,
    required super.child,
  });

  final VoidCallback onBack;

  static VoidCallback? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AelEmbeddedBackScope>()
        ?.onBack;
  }

  @override
  bool updateShouldNotify(AelEmbeddedBackScope oldWidget) =>
      onBack != oldWidget.onBack;
}
