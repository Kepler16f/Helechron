import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart' show MiuixTheme;

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/theme/ael_theme_config.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/page/legal_page.dart';
import 'package:celechron/services/consent_store.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/utils/legal_links.dart';

/// 首次启动时的隐私同意页。
///
/// 在用户勾选同意并点击“同意并继续”之前，不初始化数据库、不读取学校账号、
/// 不发起任何网络请求。同意后回调 [onAgreed] 完成应用初始化。
class ConsentApp extends StatelessWidget {
  final Future<void> Function() onAgreed;

  const ConsentApp({super.key, required this.onAgreed});

  @override
  Widget build(BuildContext context) {
    final bundle = AelThemeEngine.resolve(
      brightness: Brightness.light,
      source: ThemeColorSource.defaultBlue,
      customSeed: AelPalettePresets.defaultBlue,
      paletteStyle: ThemePaletteStyle.tonalSpot,
      contrastLevel: ThemeContrastLevel.standard,
    );
    return Theme(
      data: bundle.materialTheme,
      child: MiuixTheme(
        data: bundle.miuixTheme,
        child: CupertinoApp(
          title: 'Helechron',
          debugShowCheckedModeBanner: false,
          theme: bundle.cupertinoTheme,
          home: ConsentPage(onAgreed: onAgreed),
        ),
      ),
    );
  }
}

class ConsentPage extends StatefulWidget {
  final Future<void> Function() onAgreed;

  const ConsentPage({super.key, required this.onAgreed});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _busy = false;

  /// 同意复选框状态。默认未勾选，必须由用户主动勾选。
  ///
  /// 用 [ValueNotifier] 而不是普通字段：协议详情页是独立路由，其页脚里的
  /// 复选框与本页共用同一个状态，但路由子树不会随本页重建，用字段会导致
  /// 勾选后界面不刷新。
  final ValueNotifier<bool> _checked = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // 同意页必须全屏：原生 Tab 栏叠在 FlutterView 之上，而主应用控制其
    // 可见性的路由观察者此时还不存在，不显式隐藏就会从底部露出来。
    // 同意后由主应用的 _NativeBarVisibilityObserver 重新显示，无需恢复。
    OhosNativeService.instance.setBottomBarVisible(false);
  }

  @override
  void dispose() {
    _checked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.primaryContainer.withValues(alpha: 0.45),
              colors.pageBg,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AelIconBadge(
                        icon: AelIcons.tabFlow,
                        size: 64,
                        iconSize: 32,
                        style: AelIconBadgeStyle.cookie,
                        backgroundColor: colors.primary,
                        iconColor: colors.onPrimary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '欢迎使用 Helechron',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$appOriginStatement\n\n在开始使用前，请阅读并同意以下条款。我们会严格按照《隐私政策》处理你的信息。',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _LegalTile(
                        icon: AelIcons.shield,
                        title: '《Helechron 隐私政策》',
                        subtitle: '了解我们处理哪些信息、如何存储和保护',
                        onTap: () => _openLegal(
                          '隐私政策',
                          'assets/legal/privacy_policy.txt',
                          privacyPolicyUrl,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _LegalTile(
                        icon: AelIcons.file,
                        title: '《Helechron 用户协议》',
                        subtitle: '使用本应用的权利、义务与免责声明',
                        onTap: () => _openLegal(
                          '用户协议',
                          'assets/legal/user_agreement.txt',
                          userAgreementUrl,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AelSectionCard(
                        backgroundColor: colors.primaryContainer.withValues(
                          alpha: 0.65,
                        ),
                        child: Text(
                          '要点提示：\n'
                          '· 账号密码仅保存在你的设备本地，不会上传到我们运营的服务器；\n'
                          '· 课表、成绩、校园卡等数据来自你本人登录的学校系统；\n'
                          '· 本应用为第三方开源工具，非浙江大学官方应用，非 Celechron 官方应用；\n'
                          '· 开发者：$developerName（$developerSubjectType）；APP 备案号：$icpFilingNumber；\n'
                          '· 你可以随时退出登录、清除应用数据或卸载应用来删除本地信息。',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _ConsentActions(
                checked: _checked,
                onCheckedChanged: (value) => _checked.value = value,
                busy: _busy,
                onAgree: _agree,
                onDeny: _deny,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _agree() async {
    if (_busy) {
      return;
    }
    if (!_checked.value) {
      return;
    }
    setState(() => _busy = true);
    try {
      // 先落盘同意状态，保证后续启动不再重复弹出隐私同意页。
      await ConsentStore.agree();
      await widget.onAgreed();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      await showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('启动失败'),
          content: Text('$error\n\n请尝试重新打开应用。'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              child: const Text('退出'),
              onPressed: () {
                Navigator.of(context).pop();
                SystemNavigator.pop();
              },
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deny() async {
    final shouldExit = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('无法继续使用'),
        content: const Text('未同意隐私政策，我们不会处理你的个人信息，你将无法使用 Helechron。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('返回阅读'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('退出应用'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (shouldExit != true || !mounted) {
      return;
    }

    if (Platform.isAndroid || Platform.operatingSystem == 'ohos') {
      await SystemNavigator.pop();
      return;
    }

    if (!mounted) {
      return;
    }
    await showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('请关闭应用'),
        content: const Text('请从系统后台关闭 Helechron，或重新打开应用后选择同意。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('我知道了'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  void _openLegal(String title, String assetPath, String onlineUrl) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => LegalDocumentPage(
          title: title,
          assetPath: assetPath,
          onlineUrl: onlineUrl,
          // 协议页同样提供勾选与拒绝入口，审核时在弹窗内即可完成明示同意或拒绝。
          footer: _ConsentActions(
            checked: _checked,
            onCheckedChanged: (value) => _checked.value = value,
            busy: _busy,
            onAgree: () async {
              Navigator.of(context).pop();
              await _agree();
            },
            onDeny: () async {
              Navigator.of(context).pop();
              await _deny();
            },
          ),
        ),
      ),
    );
  }
}

/// 同意操作区：空白复选框 + 同意按钮 + 拒绝按钮。
///
/// 复选框默认未勾选，未勾选时“同意并继续”不可点击；拒绝入口始终可见。
class _ConsentActions extends StatelessWidget {
  final ValueListenable<bool> checked;
  final ValueChanged<bool> onCheckedChanged;
  final bool busy;
  final Future<void> Function() onAgree;
  final Future<void> Function() onDeny;

  const _ConsentActions({
    required this.checked,
    required this.onCheckedChanged,
    required this.busy,
    required this.onAgree,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: checked,
      builder: (context, isChecked, _) {
        final canAgree = isChecked && !busy;
        return Container(
          decoration: BoxDecoration(
            color: colors.cardBg,
            border: Border(top: BorderSide(color: colors.divider, width: 0.5)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConsentCheckbox(checked: isChecked, onChanged: onCheckedChanged),
              const SizedBox(height: 10),
              AelButton(
                expanded: true,
                label: busy ? '正在初始化...' : '同意并继续',
                icon: busy ? null : AelIcons.check,
                onPressed: canAgree ? onAgree : null,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: (!isChecked && !busy) ? 1.0 : 0.0,
                  child: Text(
                    '请先勾选上面的复选框，表示你已阅读并同意隐私政策与用户协议',
                    style: TextStyle(fontSize: 12, color: colors.textTertiary),
                  ),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: busy ? null : onDeny,
                child: Text(
                  '不同意并退出应用',
                  style: TextStyle(fontSize: 15, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 空白复选框，默认未勾选，由用户主动点击勾选。
class _ConsentCheckbox extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _ConsentCheckbox({required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: checked ? colors.primary : colors.cardBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: checked ? colors.primary : colors.outline,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? Icon(AelIcons.check, size: 16, color: colors.onPrimary)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '我已阅读并同意《Helechron 隐私政策》和《Helechron 用户协议》',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LegalTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return AelSectionCard(
      onTap: onTap,
      cornerRadius: AelRadius.tile,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          AelIconBadge(
            icon: icon,
            size: 36,
            iconSize: 18,
            style: AelIconBadgeStyle.circle,
            backgroundColor: colors.primaryContainer,
            iconColor: colors.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(AelIcons.chevronRight, size: 16, color: colors.textTertiary),
        ],
      ),
    );
  }
}
