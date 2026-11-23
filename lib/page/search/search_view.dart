import 'package:extended_sliver/extended_sliver.dart';
import 'package:flutter/cupertino.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/page/scholar/course_list/course_brief_card.dart';
import 'package:get/get.dart';
import 'package:celechron/design/theme/ael_theme.dart';

import 'search_controller.dart';

class SearchPage extends StatelessWidget {
  SearchPage({super.key});

  final _searchController = Get.put(SearchPageController());

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPinnedToBoxAdapter(
              child: Container(
                color: colors.pageBg,
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
                child: Row(
                  children: [
                    AelCircleIconButton(
                      icon: AelIcons.back,
                      size: 36,
                      iconSize: 18,
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CupertinoSearchTextField(
                        placeholder: '搜索课程、事项...',
                        backgroundColor: colors.cardBg,
                        placeholderStyle: TextStyle(
                          color: colors.textTertiary,
                          height: 1.25,
                          fontSize: 16,
                        ),
                        style: TextStyle(
                          color: colors.textPrimary,
                          height: 1.25,
                          fontSize: 16,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        itemColor: colors.textSecondary,
                        itemSize: 18,
                        suffixInsets: const EdgeInsetsDirectional.fromSTEB(
                          0,
                          0,
                          6,
                          0,
                        ),
                        prefixInsets: const EdgeInsetsDirectional.fromSTEB(
                          10,
                          0,
                          0,
                          0,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 9,
                        ),
                        onChanged: (String value) {
                          _searchController.searchWord.value = value;
                        },
                        autofocus: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Obx(() {
              final results = _searchController.courseResult;
              if (results.isEmpty &&
                  _searchController.searchWord.value.trim().isNotEmpty) {
                return const SliverPadding(
                  padding: EdgeInsets.all(AelSpacing.lg),
                  sliver: SliverToBoxAdapter(
                    child: AelEmptyState(
                      icon: AelIcons.search,
                      title: '未找到相关课程或事项',
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: index == 0
                        ? const EdgeInsets.only(
                            top: 4,
                            bottom: 5,
                            left: 16,
                            right: 16,
                          )
                        : const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 5,
                          ),
                    child: CourseBriefCard(
                      course: results[index],
                      allowDirect: true,
                    ),
                  ),
                  childCount: results.length,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
