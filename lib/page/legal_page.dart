import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 展示打包在 assets 中的法律文本，保证无网络时也能查看。
class LegalDocumentPage extends StatelessWidget {
  final String title;
  final String assetPath;
  final String? onlineUrl;

  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.assetPath,
    this.onlineUrl,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
      ),
      child: SafeArea(
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    snapshot.data!,
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
    );
  }
}
