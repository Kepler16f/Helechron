import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter_miuix/miuix.dart';
import 'package:get/get.dart';

import '../icons/ael_icons.dart';
import '../theme/ael_theme.dart';
import '../tokens/ael_tokens.dart';
import 'ael_button.dart';
import 'ael_shapes.dart';

/// 底部操作列表中的单个选项模型。
class AelActionOption<T> {
  const AelActionOption({
    this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.isSelected = false,
    this.isDestructive = false,
    this.isDefault = false,
    this.onTap,
  });

  final T? value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool isSelected;
  final bool isDestructive;
  final bool isDefault;
  final VoidCallback? onTap;
}

/// 弹窗操作按钮模型。
class AelDialogAction<T> {
  const AelDialogAction({
    required this.label,
    this.value,
    this.onPressed,
    this.variant,
    this.isDefault = false,
    this.isDestructive = false,
    this.closeOnTap = true,
  });

  final String label;
  final T? value;
  final VoidCallback? onPressed;
  final AelButtonVariant? variant;
  final bool isDefault;
  final bool isDestructive;
  final bool closeOnTap;

  AelButtonVariant get resolvedVariant {
    if (variant != null) return variant!;
    if (isDestructive) return AelButtonVariant.destructive;
    if (isDefault) return AelButtonVariant.primary;
    return AelButtonVariant.tonal;
  }
}

BuildContext? _resolvePopupContext(BuildContext? context) {
  if (context != null && context.mounted) return context;
  return Get.overlayContext ?? Get.context;
}

Future<T?> _showAelGeneralPopup<T>({
  required BuildContext context,
  required bool barrierDismissible,
  required String barrierLabel,
  required Widget Function(
    BuildContext dialogContext,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  )
  pageBuilder,
  required Widget Function(
    BuildContext dialogContext,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  )
  transitionBuilder,
}) {
  final isDark = AelTheme.colorsOf(context).isDark;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: AelSemanticPalette.pureBlack.withValues(
      alpha: isDark ? 0.56 : 0.36,
    ),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: pageBuilder,
    transitionBuilder: transitionBuilder,
  );
}

/// 统一规范的 Ael / Miuix 底部操作表，严格贴合屏幕底部，不会在鸿蒙端上浮漂移。
Future<T?> showAelActionSheet<T>({
  BuildContext? context,
  String? title,
  String? message,
  required List<AelActionOption<T>> actions,
  String cancelLabel = '取消',
  bool showCancelButton = true,
  bool barrierDismissible = true,
  double? maxWidth,
}) {
  final target = _resolvePopupContext(context);
  if (target == null) return Future<T?>.value(null);

  return showAelBottomSheet<T>(
    context: target,
    title: title,
    subtitle: message,
    isDismissible: barrierDismissible,
    maxWidth: maxWidth,
    contentPadding: EdgeInsets.zero,
    builder: (sheetCtx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AelSpacing.lg,
          0,
          AelSpacing.lg,
          AelSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: AelSpacing.sm),
                      _AelActionOptionTile<T>(
                        option: actions[i],
                        onTap: () {
                          final option = actions[i];
                          Navigator.of(sheetCtx).pop(option.value);
                          option.onTap?.call();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showCancelButton) ...[
              const SizedBox(height: AelSpacing.md),
              AelButton(
                label: cancelLabel,
                variant: AelButtonVariant.tonal,
                expanded: true,
                onPressed: () => Navigator.of(sheetCtx).pop(),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _AelActionOptionTile<T> extends StatelessWidget {
  const _AelActionOptionTile({required this.option, required this.onTap});

  final AelActionOption<T> option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    final Color bgColor;
    final Color fgColor;
    final Color subColor;
    if (option.isDestructive) {
      bgColor = colors.errorContainer.withValues(alpha: 0.65);
      fgColor = colors.error;
      subColor = colors.error.withValues(alpha: 0.78);
    } else if (option.isSelected) {
      bgColor = colors.primaryContainer;
      fgColor = colors.primary;
      subColor = colors.onPrimaryContainer.withValues(alpha: 0.78);
    } else {
      bgColor = colors.tonalTileBg;
      fgColor = colors.textPrimary;
      subColor = colors.textSecondary;
    }

    return MiuixPressable(
      onPressed: onTap,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(AelRadius.tile),
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(
          horizontal: AelSpacing.lg,
          vertical: AelSpacing.md,
        ),
        decoration: ShapeDecoration(
          color: bgColor,
          shape: AelShapes.squircle(
            AelRadius.tile,
            side: option.isSelected
                ? BorderSide(
                    color: colors.primary.withValues(alpha: 0.28),
                    width: 1,
                  )
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            if (option.icon != null) ...[
              Container(
                width: 34,
                height: 34,
                decoration: ShapeDecoration(
                  color: option.isDestructive
                      ? colors.error.withValues(alpha: 0.12)
                      : option.isSelected
                      ? colors.primary.withValues(alpha: 0.14)
                      : colors.cardBg.withValues(alpha: 0.8),
                  shape: AelShapes.squircle(AelRadius.sm),
                ),
                alignment: Alignment.center,
                child: Icon(option.icon, size: 18, color: fgColor),
              ),
              const SizedBox(width: AelSpacing.md),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    option.icon == null && option.subtitle == null
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: option.isSelected || option.isDefault
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: fgColor,
                    ),
                  ),
                  if (option.subtitle != null &&
                      option.subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: subColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (option.isSelected) ...[
              const SizedBox(width: AelSpacing.sm),
              Icon(AelIcons.check, size: 18, color: colors.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 统一规范的 Ael / Miuix 底部弹窗容器，锚定在屏幕底部且支持安全区与软键盘避让。
Future<T?> showAelBottomSheet<T>({
  required BuildContext context,
  String? title,
  String? subtitle,
  bool showDragHandle = true,
  bool showCloseButton = false,
  Widget? trailing,
  required WidgetBuilder builder,
  bool isDismissible = true,
  EdgeInsetsGeometry? contentPadding,
  double? maxHeightFactor,
  double? maxWidth,
}) {
  return _showAelGeneralPopup<T>(
    context: context,
    barrierDismissible: isDismissible,
    barrierLabel: title ?? '弹窗',
    pageBuilder: (sheetCtx, animation, secondaryAnimation) {
      final mq = MediaQuery.of(sheetCtx);
      final colors = AelTheme.colorsOf(sheetCtx);
      final isDark = colors.isDark;
      final bottomSafe = math.max(mq.padding.bottom, AelSpacing.lg);
      final hasHeader =
          (title != null && title.isNotEmpty) ||
          (subtitle != null && subtitle.isNotEmpty) ||
          showCloseButton ||
          trailing != null;

      return LayoutBuilder(
        builder: (layoutCtx, constraints) {
          final availW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : mq.size.width;
          final availH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : mq.size.height;
          final resolvedMaxWidth = maxWidth ?? (availW >= 600 ? 540.0 : availW);
          final maxHeight =
              (availH - mq.padding.top - 24) * (maxHeightFactor ?? 0.88);
          return AnimatedPadding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: resolvedMaxWidth,
                  maxHeight: math.max(180, maxHeight - mq.viewInsets.bottom),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    key: const ValueKey('ael_bottom_sheet_surface'),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.cardBg,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AelRadius.sheet),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: colors.outline.withValues(
                            alpha: isDark ? 0.28 : 0.14,
                          ),
                          width: 0.75,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AelSemanticPalette.pureBlack.withValues(
                            alpha: isDark ? 0.42 : 0.14,
                          ),
                          blurRadius: 28,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomSafe),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDragHandle)
                            Center(
                              child: Container(
                                margin: const EdgeInsets.only(
                                  top: AelSpacing.sm + 2,
                                  bottom: AelSpacing.xs,
                                ),
                                width: 38,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: colors.divider,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          if (hasHeader)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                AelSpacing.xl,
                                showDragHandle ? AelSpacing.sm : AelSpacing.lg,
                                AelSpacing.lg,
                                AelSpacing.md,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (showCloseButton && trailing == null)
                                    const SizedBox(width: 34),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          showCloseButton || trailing != null
                                          ? CrossAxisAlignment.start
                                          : CrossAxisAlignment.center,
                                      children: [
                                        if (title != null && title.isNotEmpty)
                                          Text(
                                            title,
                                            textAlign:
                                                showCloseButton ||
                                                    trailing != null
                                                ? TextAlign.start
                                                : TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: -0.2,
                                              color: colors.textPrimary,
                                            ),
                                          ),
                                        if (subtitle != null &&
                                            subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            subtitle,
                                            textAlign:
                                                showCloseButton ||
                                                    trailing != null
                                                ? TextAlign.start
                                                : TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.4,
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (trailing != null) trailing,
                                  if (showCloseButton) ...[
                                    const SizedBox(width: AelSpacing.sm),
                                    _AelHeaderCloseButton(
                                      onPressed: () =>
                                          Navigator.of(sheetCtx).pop(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          Flexible(
                            child: Padding(
                              padding:
                                  contentPadding ??
                                  const EdgeInsets.symmetric(
                                    horizontal: AelSpacing.lg,
                                  ),
                              child: builder(sheetCtx),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.16),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _AelHeaderCloseButton extends StatelessWidget {
  const _AelHeaderCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return MiuixPressable(
      onPressed: onPressed,
      feedbackType: MiuixPressFeedbackType.sink,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 34,
        height: 34,
        decoration: ShapeDecoration(
          color: colors.tonalTileBg,
          shape: AelShapes.squircle(12),
        ),
        alignment: Alignment.center,
        child: Icon(AelIcons.close, size: 16, color: colors.textSecondary),
      ),
    );
  }
}

/// 统一规范的 Ael / Miuix 对话框：手机端底部悬浮（单手易触达且随键盘上移），宽屏居中。
Future<T?> showAelDialog<T>({
  BuildContext? context,
  String? title,
  Widget? titleIcon,
  String? message,
  Widget? content,
  List<AelDialogAction<T>> actions = const [],
  bool barrierDismissible = true,
  bool center = false,
  double? maxWidth,
}) {
  final target = _resolvePopupContext(context);
  if (target == null) return Future<T?>.value(null);

  return _showAelGeneralPopup<T>(
    context: target,
    barrierDismissible: barrierDismissible,
    barrierLabel: title ?? '提示',
    pageBuilder: (dialogCtx, animation, secondaryAnimation) {
      final mq = MediaQuery.of(dialogCtx);
      final colors = AelTheme.colorsOf(dialogCtx);
      final isDark = colors.isDark;

      return LayoutBuilder(
        builder: (layoutCtx, constraints) {
          final availW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : mq.size.width;
          final availH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : mq.size.height;
          final isWide = availW >= 600 || center;
          final bottomMargin = isWide
              ? AelSpacing.xl
              : math.max(mq.padding.bottom, AelSpacing.md);
          final maxCardHeight = math.max(
            200.0,
            availH -
                mq.padding.top -
                mq.viewInsets.bottom -
                bottomMargin -
                AelSpacing.xl,
          );
          return AnimatedPadding(
            padding: EdgeInsets.fromLTRB(
              AelSpacing.md,
              mq.padding.top + AelSpacing.lg,
              AelSpacing.md,
              mq.viewInsets.bottom + bottomMargin,
            ),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Align(
              alignment: isWide ? Alignment.center : Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth ?? (isWide ? 440 : 460),
                  maxHeight: maxCardHeight,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: AelDialogSurface(
                    child: Container(
                      width: double.infinity,
                      decoration: ShapeDecoration(
                        color: colors.cardBg,
                        shape: AelShapes.squircle(
                          AelRadius.sheet,
                          side: BorderSide(
                            color: colors.outline.withValues(
                              alpha: isDark ? 0.28 : 0.14,
                            ),
                            width: 0.75,
                          ),
                        ),
                        shadows: [
                          BoxShadow(
                            color: AelSemanticPalette.pureBlack.withValues(
                              alpha: isDark ? 0.45 : 0.14,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(
                        AelSpacing.xl,
                        AelSpacing.xl,
                        AelSpacing.xl,
                        AelSpacing.lg + 2,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (titleIcon != null) ...[
                            Center(child: titleIcon),
                            const SizedBox(height: AelSpacing.md),
                          ],
                          if (title != null && title.isNotEmpty)
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: colors.textPrimary,
                              ),
                            ),
                          if (message != null && message.isNotEmpty ||
                              content != null) ...[
                            if (title != null && title.isNotEmpty)
                              const SizedBox(height: AelSpacing.sm + 2),
                            Flexible(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (message != null && message.isNotEmpty)
                                      Text(
                                        message,
                                        textAlign: content == null
                                            ? TextAlign.center
                                            : TextAlign.start,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          height: 1.5,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    if (content != null) ...[
                                      if (message != null && message.isNotEmpty)
                                        const SizedBox(height: AelSpacing.md),
                                      DefaultTextStyle.merge(
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          height: 1.5,
                                          color: colors.textPrimary,
                                        ),
                                        child: IconTheme.merge(
                                          data: IconThemeData(
                                            color: colors.textPrimary,
                                          ),
                                          child: content,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (actions.isNotEmpty) ...[
                            const SizedBox(height: AelSpacing.xl),
                            _AelDialogActionsBar<T>(
                              actions: actions,
                              dialogContext: dialogCtx,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Ael 对话框卡片标识容器，便于结构检查与组件测试定位。
class AelDialogSurface extends StatelessWidget {
  const AelDialogSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _AelDialogActionsBar<T> extends StatelessWidget {
  const _AelDialogActionsBar({
    required this.actions,
    required this.dialogContext,
  });

  final List<AelDialogAction<T>> actions;
  final BuildContext dialogContext;

  Widget _buildButton(AelDialogAction<T> action) {
    return AelButton(
      label: action.label,
      variant: action.resolvedVariant,
      expanded: true,
      onPressed: () {
        if (action.closeOnTap) {
          Navigator.of(dialogContext).pop(action.value);
        }
        action.onPressed?.call();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (actions.length == 1) {
      return _buildButton(actions.first);
    }
    if (actions.length == 2 &&
        actions[0].label.length <= 6 &&
        actions[1].label.length <= 6) {
      return Row(
        children: [
          Expanded(child: _buildButton(actions[0])),
          const SizedBox(width: AelSpacing.sm + 2),
          Expanded(child: _buildButton(actions[1])),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: AelSpacing.sm),
          _buildButton(actions[i]),
        ],
      ],
    );
  }
}

/// 单按钮提示弹窗。
Future<void> showAelAlertDialog({
  BuildContext? context,
  required String title,
  String? message,
  Widget? content,
  String confirmLabel = '确定',
  bool isDestructive = false,
  bool barrierDismissible = true,
}) {
  return showAelDialog<void>(
    context: context,
    title: title,
    message: message,
    content: content,
    barrierDismissible: barrierDismissible,
    actions: [
      AelDialogAction<void>(
        label: confirmLabel,
        variant: isDestructive
            ? AelButtonVariant.destructive
            : AelButtonVariant.primary,
      ),
    ],
  );
}

/// 二元确认弹窗（关闭或点遮罩默认返回 false）。
Future<bool> showAelConfirmDialog({
  BuildContext? context,
  required String title,
  String? message,
  Widget? content,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool isDestructive = false,
  bool barrierDismissible = true,
}) async {
  final result = await showAelDialog<bool>(
    context: context,
    title: title,
    message: message,
    content: content,
    barrierDismissible: barrierDismissible,
    actions: [
      AelDialogAction<bool>(
        label: cancelLabel,
        value: false,
        variant: AelButtonVariant.tonal,
      ),
      AelDialogAction<bool>(
        label: confirmLabel,
        value: true,
        variant: isDestructive
            ? AelButtonVariant.destructive
            : AelButtonVariant.primary,
      ),
    ],
  );
  return result ?? false;
}

/// 带单一文本输入框的 Ael 对话框。
Future<String?> showAelInputDialog({
  BuildContext? context,
  required String title,
  String? message,
  String? initialValue,
  String? placeholder,
  TextInputType? keyboardType,
  int maxLines = 1,
  bool obscureText = false,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  String? Function(String value)? validator,
}) async {
  final target = _resolvePopupContext(context);
  if (target == null) return null;

  final controller = TextEditingController(text: initialValue ?? '');
  final errorNotifier = ValueNotifier<String?>(null);

  void submit(BuildContext ctx) {
    final val = controller.text;
    final err = validator?.call(val);
    if (err != null) {
      errorNotifier.value = err;
      return;
    }
    Navigator.of(ctx, rootNavigator: true).pop(val);
  }

  try {
    return await showAelDialog<String>(
      context: target,
      title: title,
      message: message,
      content: ValueListenableBuilder<String?>(
        valueListenable: errorNotifier,
        builder: (ctx, errorText, _) {
          final colors = AelTheme.colorsOf(ctx);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                keyboardType: keyboardType,
                maxLines: maxLines,
                obscureText: obscureText,
                placeholder: placeholder,
                placeholderStyle: TextStyle(
                  fontSize: 15,
                  color: colors.textTertiary,
                ),
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.md + 2,
                  vertical: AelSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: colors.tonalTileBg,
                  borderRadius: BorderRadius.circular(AelRadius.tile),
                  border: Border.all(
                    color: errorText != null
                        ? colors.error.withValues(alpha: 0.7)
                        : colors.outline.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                onChanged: (_) {
                  if (errorNotifier.value != null) {
                    errorNotifier.value = null;
                  }
                },
                onSubmitted: (_) => submit(ctx),
              ),
              if (errorText != null) ...[
                const SizedBox(height: AelSpacing.xs + 2),
                Text(
                  errorText,
                  style: TextStyle(fontSize: 12.5, color: colors.error),
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        AelDialogAction<String>(
          label: cancelLabel,
          variant: AelButtonVariant.tonal,
        ),
        AelDialogAction<String>(
          label: confirmLabel,
          variant: AelButtonVariant.primary,
          closeOnTap: false,
          onPressed: () => submit(target),
        ),
      ],
    );
  } finally {
    controller.dispose();
    errorNotifier.dispose();
  }
}

/// 全屏滑动弹出的模态页面包装器（作为 PopupRoute 弹出，自动协调原生底栏显隐与返回键）。
Future<T?> showAelModalPage<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) {
  return _showAelGeneralPopup<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: '编辑',
    pageBuilder: (pageCtx, animation, secondaryAnimation) {
      return builder(pageCtx);
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// 滚轮选择器专用底部弹窗（统一包裹 CupertinoDatePicker / CupertinoTimerPicker / CupertinoPicker）。
Future<T?> showAelPickerSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required WidgetBuilder pickerBuilder,
  required T Function() onConfirm,
  String cancelLabel = '取消',
  String confirmLabel = '完成',
  double pickerHeight = 216,
}) {
  return showAelBottomSheet<T>(
    context: context,
    title: title,
    subtitle: subtitle,
    builder: (sheetCtx) {
      final colors = AelTheme.colorsOf(sheetCtx);
      final brightness = colors.brightness;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: pickerHeight,
            decoration: ShapeDecoration(
              color: colors.tonalTileBg,
              shape: AelShapes.squircle(AelRadius.card - 4),
            ),
            clipBehavior: Clip.antiAlias,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: brightness,
                primaryColor: colors.primary,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                  pickerTextStyle: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              child: pickerBuilder(sheetCtx),
            ),
          ),
          const SizedBox(height: AelSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AelButton(
                  label: cancelLabel,
                  variant: AelButtonVariant.tonal,
                  expanded: true,
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                ),
              ),
              const SizedBox(width: AelSpacing.md),
              Expanded(
                child: AelButton(
                  label: confirmLabel,
                  variant: AelButtonVariant.primary,
                  expanded: true,
                  onPressed: () => Navigator.of(sheetCtx).pop(onConfirm()),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}
