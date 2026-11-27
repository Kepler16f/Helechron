import 'package:flutter/cupertino.dart';

import 'package:get/get.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/option.dart';
import 'option_controller.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/icons/ael_icons.dart';

class CourseIdMappingEditForm extends StatelessWidget {
  final oldIdController = TextEditingController();
  final newIdController = TextEditingController();
  final commentController = TextEditingController();
  final String title;
  final courseIdMappingList = Get.find<OptionController>(
    tag: 'optionController',
  ).courseIdMappingList;
  final scholar = Get.find<OptionController>(tag: 'optionController').scholar;

  CourseIdMappingEditForm({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    Widget buildField(String label, TextEditingController controller) {
      return SizedBox(
        height: 50,
        child: CupertinoTextField(
          controller: controller,
          style: TextStyle(color: colors.textPrimary, fontSize: 15.5),
          placeholderStyle: TextStyle(color: colors.textTertiary),
          prefix: Padding(
            padding: const EdgeInsets.only(left: AelSpacing.lg),
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AelSpacing.md),
          decoration: BoxDecoration(
            color: colors.tonalTileBg,
            borderRadius: BorderRadius.circular(AelRadius.tile),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildField('原课号', oldIdController),
        const SizedBox(height: AelSpacing.md),
        buildField('新课号', newIdController),
        const SizedBox(height: AelSpacing.md),
        buildField('备注名', commentController),
        const SizedBox(height: AelSpacing.lg),
        AelButton(
          expanded: true,
          icon: AelIcons.check,
          label: '保存',
          onPressed: () async {
            if (oldIdController.text.isEmpty ||
                newIdController.text.isEmpty ||
                commentController.text.isEmpty) {
              await showAelAlertDialog(
                context: context,
                title: '错误',
                message: '请填写所有字段',
              );
              return;
            }
            courseIdMappingList.removeWhere(
              (element) =>
                  element.id1 == oldIdController.text ||
                  element.id2 == oldIdController.text ||
                  element.id1 == newIdController.text ||
                  element.id2 == newIdController.text,
            );
            courseIdMappingList.add(
              CourseIdMap(
                id1: oldIdController.text,
                id2: newIdController.text,
                comment: commentController.text,
              ),
            );
            if (context.mounted) Navigator.pop(context);
            await scholar.value.recalculateGpa();
            scholar.refresh();
          },
        ),
      ],
    );
  }
}

class CourseIdMappingEditPage extends StatelessWidget {
  final courseIdMappingList = Get.find<OptionController>(
    tag: 'optionController',
  ).courseIdMappingList;
  final scholar = Get.find<OptionController>(tag: 'optionController').scholar;

  CourseIdMappingEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '自定义课程代码映射'),
            Obx(() {
              if (courseIdMappingList.isEmpty) {
                return const SliverPadding(
                  padding: EdgeInsets.all(AelSpacing.pageHorizontal),
                  sliver: SliverToBoxAdapter(
                    child: AelEmptyState(
                      icon: AelIcons.layers,
                      title: '暂无自定义课程代码映射',
                      subtitle: '点击下方按钮添加新课号与原课号的映射关系',
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AelSpacing.pageHorizontal,
                  vertical: AelSpacing.sm,
                ),
                sliver: SliverToBoxAdapter(
                  child: AelConstrainedWidth(
                    maxWidth: AelBreakpointSpec.maxDetailWidth,
                    child: AelSectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AelSpacing.lg,
                        vertical: AelSpacing.xs,
                      ),
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < courseIdMappingList.length;
                            index++
                          ) ...[
                            if (index > 0)
                              Container(height: 0.5, color: colors.divider),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          courseIdMappingList[index].comment,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${courseIdMappingList[index].id1} <-> ${courseIdMappingList[index].id2}',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  AelCircleIconButton(
                                    icon: AelIcons.delete,
                                    size: 32,
                                    iconSize: 15,
                                    backgroundColor: colors.errorContainer,
                                    iconColor: colors.onErrorContainer,
                                    elevated: false,
                                    tooltip: '删除映射',
                                    onPressed: () async {
                                      courseIdMappingList.removeAt(index);
                                      await scholar.value.recalculateGpa();
                                      scholar.refresh();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AelSpacing.pageHorizontal,
                vertical: AelSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: AelConstrainedWidth(
                  maxWidth: AelBreakpointSpec.maxDetailWidth,
                  child: AelButton(
                    expanded: true,
                    variant: AelButtonVariant.tonal,
                    icon: AelIcons.add,
                    label: '添加新的映射关系',
                    onPressed: () {
                      showAelBottomSheet<void>(
                        context: context,
                        title: '添加新的映射关系',
                        showCloseButton: true,
                        builder: (_) =>
                            CourseIdMappingEditForm(title: '添加新的映射关系'),
                      );
                    },
                  ),
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
