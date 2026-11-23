import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher_string.dart';

class CustomLicensePage extends StatelessWidget {
  const CustomLicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '服务条款'),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AelSpacing.pageHorizontal,
                vertical: AelSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AelSectionCard(
                      title: '免责声明',
                      icon: AelIcons.shield,
                      child: Text(
                        '在适用的法律范围内，该程序不提供任何质量保证。除非另有书面说明，版权持有者和程序提供者应按照原样提供程序，并且不提供任何明示或者暗示的保证，包括但不限于适销性和特定用途适用性的暗示保证。使用该程序所产生的全部风险，比如程序的质量和性能问题，全部由你承担。如果程序出现缺陷，你将承担所有必要的修复和更正服务带来的损失。',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AelSpacing.md),
                    AelSectionCard(
                      title: '责任限制',
                      icon: AelIcons.info,
                      child: Text(
                        '除非有适用法律或书面协议要求，任何版权持有者，或该程序按照本协议可能存在的第三方修改和再发布者，都不对你的损失负有责任，包括由于使用或者不能使用该程序造成的任何一般的、特殊的、偶发的或重大的损失（包括但不限于数据丢失、数据失真、你或第三方的后续损失、该程序无法和其他程序协同工作等），即使他们声称会对此负责。',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AelSpacing.lg),
                    AelButton(
                      expanded: true,
                      variant: AelButtonVariant.tonal,
                      icon: AelIcons.externalLink,
                      label: '查看 GPLv3 协议全文',
                      onPressed: () async {
                        await launchUrlString(
                          'https://www.gnu.org/licenses/gpl-3.0.html',
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: NativeBottomBarSpacer()),
          ],
        ),
      ),
    );
  }
}
