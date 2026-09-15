import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/http/github_service.dart';

class CreditsPage extends StatefulWidget {
  final String version;
  const CreditsPage({required this.version, super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  List<String> _contributors = [];
  bool _isLoading = true;
  final _githubService = GitHubService();
  final _httpClient = HttpClient();

  @override
  void initState() {
    super.initState();
    _loadContributors();
  }

  Future<void> _loadContributors() async {
    try {
      var result = await _githubService.getContributors(_httpClient);
      setState(() {
        _contributors = result.item2;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _contributors = GitHubService.defaultContributors;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  Widget _buildContributorsList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: CupertinoActivityIndicator(),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: _buildContributorRows(),
      ),
    );
  }

  List<Widget> _buildContributorRows() {
    List<Widget> rows = [];
    for (int i = 0; i < _contributors.length; i += 2) {
      List<Widget> children = [];

      children.add(
        Expanded(
          child: Text(
            _contributors[i],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );

      if (i + 1 < _contributors.length) {
        children.add(
          Expanded(
            child: Text(
              _contributors[i + 1],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        );
      }

      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          verticalDirection: VerticalDirection.down,
          children: children,
        ),
      );

      if (i + 2 < _contributors.length) {
        rows.add(const SizedBox(height: 8));
      }
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '关于'),
            SliverToBoxAdapter(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 64,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        "assets/logo.png",
                        height: 108,
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Column(
                        children: [
                          const Text(
                            'Helechron',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 32,
                            ),
                          ),
                          Text(
                            '${widget.version} 版本',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Celechron 的 OpenHarmony 移植版本，\n基于上游 1.3.0，有问题请到仓库反馈',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.secondaryLabel, context),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  const Text(
                    '制作人员',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      verticalDirection: VerticalDirection.down,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Kepler16f',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  const Text(
                    '上游制作人员',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  const Text(
                    '🎨设计',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      verticalDirection: VerticalDirection.down,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'nosig',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '空之探险队的 Kate',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  const Text(
                    '🧑‍💻开发',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  _buildContributorsList(),
                ],
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '本程序采用 GPLv3 协议开源',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context)),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  GestureDetector(
                    onTap: () {
                      // 可以后续接入 url_launcher 跳转仓库
                    },
                    child: Text(
                      'Helechron 项目网站',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.activeBlue, context),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  GestureDetector(
                    onTap: () {
                      // 可以后续接入 url_launcher 跳转上游仓库
                    },
                    child: Text(
                      '上游 Celechron 项目网站',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.activeBlue, context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
