import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import 'package:celechron/design/components/ael_glass.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';

class AelTabItem {
  const AelTabItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Android / iOS 端使用的 FlClash 风格导航底栏（鸿蒙端由 ArkTS 原生 `HdsTabs` 托管，不渲染此组件）：
/// - 悬浮模式下：居中胶囊 Dock + 物理弹簧驱动的可拖拽透镜滑块 + 双层裁切动态着色
/// - 沉浸光感开启时：在胶囊与透镜上启用液态玻璃折射模糊与镜面边缘高光（页面被二级路由覆盖时自动暂停模糊捕获）
/// - 停靠模式下：FlClash NavigationBar 风格全宽底栏，带水平展开高亮胶囊指示器
class AelTabBar extends StatelessWidget {
  const AelTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    required this.floating,
    required this.immersiveLight,
    this.materialLevel = 10,
    this.captureActive = true,
  });

  final List<AelTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool floating;
  final bool immersiveLight;
  final int materialLevel;
  final bool captureActive;

  void _handleSelect(int index) {
    HapticFeedback.selectionClick();
    onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = AelTheme.colorsOf(context);
    final bottomInset = media.padding.bottom;

    if (!floating) {
      return _buildDockedBar(context, colors, bottomInset);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AelTabBarSpec.dockHorizontalMargin,
        0,
        AelTabBarSpec.dockHorizontalMargin,
        bottomInset + AelTabBarSpec.dockBottomMargin,
      ),
      child: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AelTabBarSpec.dockMaxWidth,
          ),
          child: _FlClashFloatingDock(
            items: items,
            currentIndex: currentIndex,
            onSelect: _handleSelect,
            immersiveLight: immersiveLight,
            quality: AelGlassQuality.fromMaterialLevel(materialLevel),
            captureActive: captureActive,
          ),
        ),
      ),
    );
  }

  Widget _buildDockedBar(
    BuildContext context,
    AelColorTokens colors,
    double bottomInset,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBg,
        border: Border(
          top: BorderSide(
            color: colors.divider.withValues(
              alpha: colors.isDark ? 0.35 : 0.45,
            ),
            width: 0.5,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: AelTabBarSpec.dockedBarHeight,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _DockedTabDestination(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => _handleSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockedTabDestination extends StatelessWidget {
  const _DockedTabDestination({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AelTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final fg = selected ? colors.primary : colors.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 58,
              height: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: selected ? 1.0 : 0.0),
                    duration: AelDurations.normal,
                    curve: Curves.easeInOutCubic,
                    builder: (context, t, _) {
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scaleX: 0.35 + 0.65 * t,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              color: colors.primaryContainer,
                              shape: const StadiumBorder(),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      );
                    },
                  ),
                  Icon(item.icon, size: 22, color: fg),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AelTabBarSpec.dockLabelSize,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colors.textPrimary : colors.textSecondary,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FlClash NavigationDock 风格的弹簧透镜悬浮胶囊底栏。
class _FlClashFloatingDock extends StatefulWidget {
  const _FlClashFloatingDock({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    required this.immersiveLight,
    required this.quality,
    required this.captureActive,
  });

  final List<AelTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool immersiveLight;
  final AelGlassQuality quality;
  final bool captureActive;

  @override
  State<_FlClashFloatingDock> createState() => _FlClashFloatingDockState();
}

class _FlClashFloatingDockState extends State<_FlClashFloatingDock>
    with TickerProviderStateMixin {
  static final _travelSpring = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 380),
    bounce: 0.14,
  );
  static final _followSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 920,
    ratio: 0.88,
  );
  static final _liftSpring = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 220),
  );
  static final _glowOutSpring = SpringDescription.withDurationAndBounce(
    duration: const Duration(milliseconds: 420),
  );

  late final AnimationController _lensController;
  late final AnimationController _liftController;
  late final AnimationController _glowController;

  int? _activePointer;
  int? _pressedIndex;
  double _pressX = 0;
  bool _dragging = false;
  Offset? _glowPosition;
  double _pillWidth = 0;

  @override
  void initState() {
    super.initState();
    _lensController = AnimationController.unbounded(
      vsync: this,
      value: widget.currentIndex.toDouble(),
    );
    _liftController = AnimationController.unbounded(vsync: this, value: 0.0);
    _glowController = AnimationController.unbounded(vsync: this, value: 0.0);
  }

  @override
  void didUpdateWidget(covariant _FlClashFloatingDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex && !_dragging) {
      _springTo(_lensController, widget.currentIndex.toDouble(), _travelSpring);
    }
  }

  @override
  void dispose() {
    _lensController.dispose();
    _liftController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _springTo(
    AnimationController controller,
    double target,
    SpringDescription spring,
  ) {
    final simulation = SpringSimulation(
      spring,
      controller.value,
      target,
      controller.velocity,
    );
    controller.animateWith(simulation);
  }

  int get _count => widget.items.length;

  double _positionFromLocalX(double dx, double innerWidth) {
    if (_count <= 1 || innerWidth <= 0) return 0;
    final cellWidth = innerWidth / _count;
    final raw = (dx - AelTabBarSpec.dockPadding) / cellWidth - 0.5;
    return raw.clamp(-0.22, _count - 1 + 0.22);
  }

  int _nearestIndex(double position) {
    if (_count <= 1) return 0;
    return position.round().clamp(0, _count - 1);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null || _count == 0) return;
    _activePointer = event.pointer;
    final innerWidth = math.max(
      1.0,
      _pillWidth - AelTabBarSpec.dockPadding * 2,
    );
    final pos = _positionFromLocalX(event.localPosition.dx, innerWidth);
    final index = _nearestIndex(pos);
    _pressedIndex = index;
    _pressX = event.localPosition.dx;
    _dragging = false;
    setState(() {
      _glowPosition = event.localPosition;
    });
    _springTo(_liftController, 1.0, _liftSpring);
    _springTo(_glowController, 1.0, _liftSpring);
    if (index != widget.currentIndex) {
      _springTo(_lensController, index.toDouble(), _travelSpring);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _count == 0) return;
    final innerWidth = math.max(
      1.0,
      _pillWidth - AelTabBarSpec.dockPadding * 2,
    );
    if (!_dragging && (event.localPosition.dx - _pressX).abs() > 6.0) {
      _dragging = true;
    }
    setState(() {
      _glowPosition = event.localPosition;
    });
    if (!_dragging) return;
    final pos = _positionFromLocalX(event.localPosition.dx, innerWidth);
    _springTo(_lensController, pos, _followSpring);
    final nearest = _nearestIndex(pos);
    if (nearest != _pressedIndex) {
      HapticFeedback.selectionClick();
      _pressedIndex = nearest;
    }
  }

  void _onPointerEnd(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    _activePointer = null;
    final commit = event is PointerUpEvent;
    final target = commit
        ? (_pressedIndex ?? widget.currentIndex).clamp(0, _count - 1)
        : widget.currentIndex;
    _pressedIndex = null;
    _dragging = false;
    _springTo(_lensController, target.toDouble(), _travelSpring);
    _springTo(_liftController, 0.0, _liftSpring);
    _springTo(_glowController, 0.0, _glowOutSpring);
    if (commit && target != widget.currentIndex) {
      widget.onSelect(target);
    }
  }

  Rect _lensRectFor(
    double innerWidth,
    double height,
    double lensPos,
    double lift,
  ) {
    if (_count <= 0) return Rect.zero;
    final cellWidth = innerWidth / _count;
    final spread = lerpDouble(0, 5.5, lift)!;
    final verticalInset = lerpDouble(
      AelTabBarSpec.dockPadding,
      AelTabBarSpec.dockPadding - 1.5,
      lift,
    )!;
    final left = AelTabBarSpec.dockPadding + lensPos * cellWidth - spread * 0.5;
    final width = cellWidth + spread;
    return Rect.fromLTWH(
      left.clamp(2.0, math.max(2.0, _pillWidth - width - 2.0)),
      verticalInset,
      width,
      math.max(0.0, height - verticalInset * 2),
    );
  }

  Widget _buildItemsRow({
    required BuildContext context,
    required AelColorTokens colors,
    required bool highlighted,
    required double lift,
  }) {
    final color = highlighted ? colors.primary : colors.textSecondary;
    final scale = highlighted ? (1.0 + 0.05 * lift) : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AelTabBarSpec.dockPadding,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _count; i++)
            Expanded(
              child: highlighted
                  ? ExcludeSemantics(
                      child: Transform.scale(
                        scale: scale,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.items[i].icon,
                              size: AelTabBarSpec.dockIconSize,
                              color: color,
                            ),
                            const SizedBox(height: 1.5),
                            Text(
                              widget.items[i].label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AelTabBarSpec.dockLabelSize,
                                fontWeight: FontWeight.w600,
                                color: color,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Semantics(
                      button: true,
                      selected: i == widget.currentIndex,
                      label: widget.items[i].label,
                      child: Transform.scale(
                        scale: scale,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.items[i].icon,
                              size: AelTabBarSpec.dockIconSize,
                              color: color,
                            ),
                            const SizedBox(height: 1.5),
                            Text(
                              widget.items[i].label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AelTabBarSpec.dockLabelSize,
                                fontWeight: FontWeight.w500,
                                color: color,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final isDark = colors.isDark;
    final glassEnabled = widget.immersiveLight && widget.captureActive;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: SizedBox(
        height: AelTabBarSpec.dockHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _pillWidth = constraints.maxWidth;
            final innerWidth = math.max(
              0.0,
              _pillWidth - AelTabBarSpec.dockPadding * 2,
            );
            return AnimatedBuilder(
              animation: Listenable.merge([
                _lensController,
                _liftController,
                _glowController,
              ]),
              builder: (context, _) {
                final lensRect = _lensRectFor(
                  innerWidth,
                  AelTabBarSpec.dockHeight,
                  _lensController.value,
                  _liftController.value,
                );
                final lift = _liftController.value.clamp(0.0, 1.0);
                final outerContent = Stack(
                  fit: StackFit.expand,
                  children: [
                    // 外部未选中图层
                    _buildItemsRow(
                      context: context,
                      colors: colors,
                      highlighted: false,
                      lift: 0,
                    ),
                    // 弹簧悬浮透镜指示器
                    Positioned.fromRect(
                      rect: lensRect,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: widget.immersiveLight
                              ? (isDark
                                    ? AelGlassTokens.darkLensTint
                                    : AelGlassTokens.lightLensTint)
                              : colors.primaryContainer.withValues(
                                  alpha: 0.72 + 0.14 * lift,
                                ),
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: widget.immersiveLight
                                  ? (isDark
                                        ? AelGlassTokens.darkRimHighlight
                                              .withValues(
                                                alpha: 0.34 + 0.24 * lift,
                                              )
                                        : AelGlassTokens.lightRimHighlight
                                              .withValues(alpha: 0.85))
                                  : colors.primary.withValues(alpha: 0.16),
                              width: widget.immersiveLight ? 0.9 : 0.6,
                            ),
                          ),
                          shadows: [
                            BoxShadow(
                              color: isDark
                                  ? AelGlassTokens.darkLensShadow
                                  : AelGlassTokens.lightLensShadow,
                              blurRadius: lerpDouble(8, 16, lift)!,
                              offset: Offset(0, lerpDouble(2, 5, lift)!),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 透镜内部裁切高亮图层
                    ClipPath(
                      clipper: _CapsuleRectClipper(lensRect),
                      child: _buildItemsRow(
                        context: context,
                        colors: colors,
                        highlighted: true,
                        lift: lift,
                      ),
                    ),
                  ],
                );

                return AelGlassSurface(
                  borderRadius: AelTabBarSpec.dockHeight / 2,
                  isCapsule: true,
                  reduceTransparency: !widget.immersiveLight,
                  enableBackdrop: glassEnabled,
                  quality: widget.quality,
                  blurSigma: 18.0,
                  glowCenter: widget.immersiveLight ? _glowPosition : null,
                  glowStrength: _glowController.value,
                  child: outerContent,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CapsuleRectClipper extends CustomClipper<Path> {
  const _CapsuleRectClipper(this.rect);

  final Rect rect;

  @override
  Path getClip(Size size) {
    final radius = rect.shortestSide / 2;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
  }

  @override
  bool shouldReclip(_CapsuleRectClipper oldClipper) => rect != oldClipper.rect;
}

/// Android / iOS 平板与横屏宽屏使用的左侧导航栏（>= 600dp 时替代底部栏）。
class AelSideRail extends StatelessWidget {
  const AelSideRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    required this.floating,
    required this.immersiveLight,
    this.materialLevel = 10,
    this.captureActive = true,
  });

  final List<AelTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool floating;
  final bool immersiveLight;
  final int materialLevel;
  final bool captureActive;

  void _handleSelect(int index) {
    HapticFeedback.selectionClick();
    onSelect(index);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = AelTheme.colorsOf(context);
    final leftSafe = media.padding.left;
    final topSafe = media.padding.top;
    final bottomSafe = media.padding.bottom;

    if (!floating) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cardBg,
          border: Border(
            right: BorderSide(
              color: colors.divider.withValues(alpha: 0.45),
              width: 0.5,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            leftSafe,
            topSafe + 12,
            0,
            bottomSafe + 12,
          ),
          child: SizedBox(
            width: AelTabBarSpec.sideRailWidth,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildRailButtons(context, colors, compact: false),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        leftSafe + 10,
        topSafe + 14,
        6,
        bottomSafe + 14,
      ),
      child: Center(
        widthFactor: 1.0,
        child: SizedBox(
          width: AelTabBarSpec.sideRailFloatingWidth,
          child: AelGlassSurface(
            borderRadius: AelTabBarSpec.borderRadius,
            reduceTransparency: !immersiveLight,
            enableBackdrop: immersiveLight && captureActive,
            quality: AelGlassQuality.fromMaterialLevel(materialLevel),
            blurSigma: 18,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildRailButtons(context, colors, compact: true),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRailButtons(
    BuildContext context,
    AelColorTokens colors, {
    required bool compact,
  }) {
    final list = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) list.add(SizedBox(height: compact ? 6 : 8));
      final item = items[i];
      final active = i == currentIndex;
      list.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleSelect(i),
          child: Semantics(
            button: true,
            selected: active,
            label: item.label,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: AelDurations.normal,
                    curve: Curves.easeInOutCubic,
                    width: compact ? 48 : 56,
                    height: 32,
                    decoration: ShapeDecoration(
                      color: active
                          ? colors.primaryContainer
                          : AelSemanticPalette.transparent,
                      shape: const StadiumBorder(),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.icon,
                      size: 21,
                      color: active
                          ? colors.onPrimaryContainer
                          : colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AelTabBarSpec.labelFontSize,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active ? colors.primary : colors.textSecondary,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return list;
  }
}
