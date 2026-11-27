import 'package:celechron/design/native_bar_spacer.dart';
import 'package:celechron/design/persistent_headers.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

import 'option_controller.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/design/icons/ael_icons.dart';

String timeToString(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

class DateTimePair {
  DateTime first, second;
  bool isDeleted;
  DateTimePair({
    required this.first,
    required this.second,
    this.isDeleted = false,
  });
}

Future<void> showDateTimePairEditSheet(
  BuildContext context, {
  required DateTimePair val,
  required ValueChanged<DateTimePair> onChanged,
}) async {
  DateTimePair draft = DateTimePair(first: val.first, second: val.second);
  await showAelBottomSheet<void>(
    context: context,
    title: '更改时段',
    showCloseButton: true,
    builder: (sheetCtx) {
      return StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final colors = AelTheme.colorsOf(sheetCtx);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AelListRow(
                title: '开始时间',
                icon: AelIcons.tabFlow,
                trailing: Text(
                  timeToString(draft.first),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                onTap: () async {
                  DateTime temp = draft.first;
                  final picked = await showAelPickerSheet<DateTime>(
                    context: sheetCtx,
                    title: '选择开始时间',
                    pickerBuilder: (_) => CupertinoDatePicker(
                      initialDateTime: temp,
                      use24hFormat: true,
                      minuteInterval: 1,
                      mode: CupertinoDatePickerMode.time,
                      onDateTimeChanged: (t) => temp = t,
                    ),
                    onConfirm: () => temp,
                  );
                  if (picked != null) {
                    setSheetState(() => draft.first = picked);
                  }
                },
              ),
              const SizedBox(height: AelSpacing.sm),
              AelListRow(
                title: '结束时间',
                icon: AelIcons.tabFlow,
                trailing: Text(
                  timeToString(draft.second),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                onTap: () async {
                  DateTime temp = draft.second;
                  final picked = await showAelPickerSheet<DateTime>(
                    context: sheetCtx,
                    title: '选择结束时间',
                    pickerBuilder: (_) => CupertinoDatePicker(
                      initialDateTime: temp,
                      use24hFormat: true,
                      minuteInterval: 1,
                      mode: CupertinoDatePickerMode.time,
                      onDateTimeChanged: (t) => temp = t,
                    ),
                    onConfirm: () => temp,
                  );
                  if (picked != null) {
                    setSheetState(() => draft.second = picked);
                  }
                },
              ),
              const SizedBox(height: AelSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AelButton(
                      label: '取消',
                      variant: AelButtonVariant.tonal,
                      expanded: true,
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ),
                  const SizedBox(width: AelSpacing.md),
                  Expanded(
                    child: AelButton(
                      label: '确定',
                      expanded: true,
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        onChanged(draft);
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

class DateTimePairEditDialog extends StatefulWidget {
  final DateTimePair val;
  final Function(DateTimePair pair)? onChanged;
  const DateTimePairEditDialog({super.key, required this.val, this.onChanged});
  @override
  State<DateTimePairEditDialog> createState() => _DateTimePairEditDialogState();
}

class _DateTimePairEditDialogState extends State<DateTimePairEditDialog> {
  late DateTimePair val;
  @override
  void initState() {
    super.initState();
    val = DateTimePair(first: widget.val.first, second: widget.val.second);
  }

  void saveChange() {
    if (widget.onChanged != null) {
      widget.onChanged!(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class AllowTimeEditPage extends StatefulWidget {
  const AllowTimeEditPage({super.key});

  @override
  State<AllowTimeEditPage> createState() => _AllowTimeEditPageState();
}

class _AllowTimeEditPageState extends State<AllowTimeEditPage> {
  final _optionController = Get.find<OptionController>(tag: 'optionController');
  List<DateTimePair> now = [];
  int __got = 0;

  void getAllowTime() {
    now.clear();
    for (var x in _optionController.allowTime.keys) {
      now.add(
        DateTimePair(
          first: x.copyWith(),
          second: _optionController.allowTime[x]!.copyWith(),
        ),
      );
    }
    now.sort((DateTimePair a, DateTimePair b) {
      if (a.first.compareTo(b.first) != 0) {
        return a.first.compareTo(b.first);
      }
      return a.second.compareTo(b.second);
    });
    setState(() {});
  }

  void saveAllowTime() async {
    for (int i = 0; i < now.length; i++) {
      var x = now[i];

      if (!x.first.isBefore(x.second)) {
        await showAelAlertDialog(
          context: context,
          title: '时间设置无效',
          message: '开始时间必须早于结束时间',
        );
        getAllowTime();
        return;
      }

      for (int j = 0; j < now.length; j++) {
        if (i == j) continue;
        var y = now[j];
        if ((!x.first.isBefore(y.first) && !x.first.isAfter(y.second)) ||
            (!x.second.isBefore(y.first) && !x.second.isAfter(y.second))) {
          await showAelAlertDialog(
            context: context,
            title: '时间设置冲突',
            message: '时间段之间不能有重合或直接相邻',
          );
          getAllowTime();
          return;
        }
      }
    }

    FormState().save();
    Map<DateTime, DateTime> res = {};
    for (var x in now) {
      res[x.first] = x.second;
    }

    _optionController.allowTime = res;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    if (__got == 0) {
      getAllowTime();
      __got = 1;
    }

    now.removeWhere((element) => element.isDeleted);

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const CelechronSliverTextHeader(subtitle: '编辑可用工作时段'),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AelSpacing.pageHorizontal,
                vertical: AelSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: AelConstrainedWidth(
                  maxWidth: AelBreakpointSpec.maxDetailWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AelSectionCard(
                        title: '可用工作时段列表',
                        icon: AelIcons.tabFlow,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AelSpacing.lg,
                          vertical: AelSpacing.md,
                        ),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < now.length;
                              index++
                            ) ...[
                              if (index > 0)
                                Container(height: 0.5, color: colors.divider),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${timeToString(now[index].first)} - ${timeToString(now[index].second)}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    AelCircleIconButton(
                                      icon: AelIcons.edit,
                                      size: 32,
                                      iconSize: 15,
                                      backgroundColor: colors.primaryContainer,
                                      iconColor: colors.onPrimaryContainer,
                                      elevated: false,
                                      tooltip: '编辑时段',
                                      onPressed: () {
                                        showDateTimePairEditSheet(
                                          context,
                                          val: now[index],
                                          onChanged: (DateTimePair updated) {
                                            setState(() {
                                              now[index] = DateTimePair(
                                                first: updated.first,
                                                second: updated.second,
                                                isDeleted: updated.isDeleted,
                                              );
                                              saveAllowTime();
                                            });
                                          },
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    AelCircleIconButton(
                                      icon: AelIcons.delete,
                                      size: 32,
                                      iconSize: 15,
                                      backgroundColor: colors.errorContainer,
                                      iconColor: colors.onErrorContainer,
                                      elevated: false,
                                      tooltip: '删除时段',
                                      onPressed: () {
                                        if (now.length > 1) {
                                          setState(() {
                                            now.removeAt(index);
                                            saveAllowTime();
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AelSpacing.md),
                      AelButton(
                        expanded: true,
                        variant: AelButtonVariant.tonal,
                        icon: AelIcons.add,
                        label: '添加一个时段',
                        onPressed: () {
                          now.add(
                            DateTimePair(
                              first: DateTime(0, 0, 0, 8, 0),
                              second: DateTime(0, 0, 0, 12, 0),
                              isDeleted: false,
                            ),
                          );
                          setState(() {});
                        },
                      ),
                    ],
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
