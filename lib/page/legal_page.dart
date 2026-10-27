import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/utils/legal_links.dart';

/// 展示打包在 assets 中的法律文本，保证无网络时也能查看。
///
/// 文本中的 `{{DEVELOPER_NAME}}` 等占位符会替换为构建时注入的开发者信息，
/// 保证应用内文本与商店在线版本（`docs/*.html`）展示同一个主体名称与备案号。
class LegalDocumentPage extends StatelessWidget {
  final String title;
  final String assetPath;
  final String? onlineUrl;

  /// 底部固定操作区。首次启动同意页用它承载“勾选 + 同意 / 不同意”，
  /// 让用户在阅读协议的界面上同样能明确同意或拒绝。
  final Widget? footer;

  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.assetPath,
    this.onlineUrl,
    this.footer,
  });

  static String resolvePlaceholders(String raw) {
    var text = raw;
    legalPlaceholders.forEach((key, value) {
      text = text.replaceAll(key, value);
    });
    return text;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: rootBundle.loadString(assetPath),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '文档加载失败：${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          resolvePlaceholders(snapshot.data!),
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.65,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label,
                              context,
                            ),
                          ),
                        ),
                        if (onlineUrl != null && onlineUrl!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => launchUrlString(
                              onlineUrl!,
                              mode: LaunchMode.externalApplication,
                            ),
                            child: const Text('在线查看最新版本'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
