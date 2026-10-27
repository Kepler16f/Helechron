import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:celechron/page/legal_page.dart';
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
    return CupertinoApp(
      title: 'Helechron',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(brightness: Brightness.light),
      home: ConsentPage(onAgreed: onAgreed),
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
  static const _primary = Color(0xFF3478F6);
  static const _secondaryText = Color(0xFF6B6B70);

  bool _busy = false;

  /// 同意复选框状态。默认未勾选，必须由用户主动勾选。
  ///
  /// 用 [ValueNotifier] 而不是普通字段：协议详情页是独立路由，其页脚里的
  /// 复选框与本页共用同一个状态，但路由子树不会随本页重建，用字段会导致
  /// 勾选后界面不刷新。
  final ValueNotifier<bool> _checked = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _checked.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2F7FF), Color(0xFFFFFFFF)],
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
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: _primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          CupertinoIcons.time,
                          color: CupertinoColors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '欢迎使用 Helechron',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: CupertinoColors.black,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '在开始使用前，请阅读并同意以下条款。我们会严格按照《隐私政策》处理你的信息。',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: _secondaryText,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _LegalTile(
                        icon: CupertinoIcons.lock,
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
                        icon: CupertinoIcons.doc_text,
                        title: '《Helechron 用户协议》',
                        subtitle: '使用本应用的权利、义务与免责声明',
                        onTap: () => _openLegal(
                          '用户协议',
                          'assets/legal/user_agreement.txt',
                          userAgreementUrl,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '要点提示：\n'
                          '· 账号密码仅保存在你的设备本地，不会上传到我们运营的服务器；\n'
                          '· 课表、成绩、校园卡等数据来自你本人登录的学校系统；\n'
                          '· 本应用为第三方开源工具，非浙江大学官方应用，非 Celechron 官方应用；\n'
                          '· 开发者：$developerName（$developerSubjectType）；APP 备案号：$icpFilingNumber；\n'
                          '· 你可以随时退出登录、清除应用数据或卸载应用来删除本地信息。',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.65,
                            color: Color(0xFF3D3D42),
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
        content: const Text(
          '未同意隐私政策，我们不会处理你的个人信息，你将无法使用 Helechron。',
        ),
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
    return ValueListenableBuilder<bool>(
      valueListenable: checked,
      builder: (context, isChecked, _) {
        final canAgree = isChecked && !busy;
        return Container(
          decoration: const BoxDecoration(
            color: CupertinoColors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE3E8F0), width: 0.5),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConsentCheckbox(
                checked: isChecked,
                onChanged: onCheckedChanged,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: _ConsentPageState._primary,
                  disabledColor: const Color(0xFFBFC9D8),
                  borderRadius: BorderRadius.circular(12),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  onPressed: canAgree ? onAgree : null,
                  child: busy
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : const Text(
                          '同意并继续',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              if (!isChecked)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '请先勾选上面的复选框，表示你已阅读并同意隐私政策与用户协议',
                    style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                  ),
                ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: busy ? null : onDeny,
                child: const Text(
                  '不同意并退出应用',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF8E8E93),
                  ),
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
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => onChanged(!checked),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: checked
                  ? _ConsentPageState._primary
                  : CupertinoColors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: checked
                    ? _ConsentPageState._primary
                    : const Color(0xFFB8BEC9),
                width: 1.5,
              ),
            ),
            child: checked
                ? const Icon(
                    CupertinoIcons.check_mark,
                    size: 18,
                    color: CupertinoColors.white,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                '我已阅读并同意《Helechron 隐私政策》和《Helechron 用户协议》',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: _ConsentPageState._secondaryText,
                ),
              ),
            ),
          ),
        ],
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
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _ConsentPageState._primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _ConsentPageState._secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_forward,
              size: 16,
              color: Color(0xFFB0B4BB),
            ),
          ],
        ),
      ),
    );
  }
}
