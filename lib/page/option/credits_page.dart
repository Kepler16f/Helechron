import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/http/github_service.dart';
import 'package:celechron/utils/legal_links.dart';

class CreditsPage extends StatefulWidget {
  final String version;
  const CreditsPage({required this.version, super.key});

  @override
  State<CreditsPage> createState() => _CreditsPageState();
}

class _CreditsPageState extends State<CreditsPage> {
  List<String> _contributors = List<String>.from(
    GitHubService.defaultContributors,
  );
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
      if (!mounted) return;
      if (result.item2.isNotEmpty) {
        setState(() {
          _contributors = result.item2;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contributors = List<String>.from(GitHubService.defaultContributors);
      });
    }
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }

  Widget _buildContributorsList() {
    final list = _contributors.isNotEmpty
        ? _contributors
        : GitHubService.defaultContributors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _buildContributorRows(list),
      ),
    );
  }

  List<Widget> _buildContributorRows(List<String> contributors) {
    List<Widget> rows = [];
    for (int i = 0; i < contributors.length; i += 2) {
      final String left = contributors[i];
      final String? right =
          (i + 1 < contributors.length) ? contributors[i + 1] : null;

      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    left,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ),
              ),
              if (right != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      right,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.35),
                    ),
                  ),
                )
              else
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      );
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        bottom: false,
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
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      '$appOriginStatement\n'
                      '与 Celechron 原项目及浙江大学无隶属、品牌授权、合作或背书关系。\n'
                      '以下上游署名仅说明代码与设计来源，不代表原作者参与本应用的发布或运营。'
                      '本应用按 GPL-3.0 开源，有问题请到 Helechron 仓库反馈。\n'
                      'APP 备案号：$icpFilingNumber',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  const Text(
                    'Helechron 移植、开发与维护',
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
                            developerName,
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
                    '开源来源致谢：Celechron',
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
                  const SizedBox(height: 24),
                  const Text(
                    '参考与致谢开源项目',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      '• Celechron/Celechron (github.com/Celechron/Celechron)\n'
                      '• Elyyyyyyyyxer/Elychron (github.com/Elyyyyyyyyxer/Elychron)\n'
                      '• 5dbwat4/login-ZJU (github.com/5dbwat4/login-ZJU)\n'
                      '• PeiPei233/zju-learning-assistant (github.com/PeiPei233/zju-learning-assistant)\n'
                      '• 8eoyw/zju-learning-cli (github.com/8eoyw/zju-learning-cli)\n'
                      '• Anchorite-no/zju-skill-public (github.com/Anchorite-no/zju-skill-public)\n'
                      '• Lucent-Snow/zju-scholar & iamNCJ/ZJU-Tronclass-Courseware-Downloader\n'
                      '• determ1ne/zju_ecard、OpenAHU/AHUTong-Android、Mercury000/HUEL-yktwx、Chiu-xaH/HFUT-Schedule\n'
                      '• OpenHarmony-TPC/flutter_flutter (gitcode.com/openharmony-tpc/flutter_flutter)',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel, context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
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
                  Text(
                    'github.com/Kepler16f/Helechron',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel, context),
                    ),
                  ),
                  const NativeBottomBarSpacer(extra: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
