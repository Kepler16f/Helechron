import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/cupertino_async_switch.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/theme/ael_theme.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/option.dart';
import 'package:celechron/page/legal_page.dart';
import 'package:celechron/services/ohos_native_service.dart';
import 'package:celechron/utils/legal_links.dart';
import 'package:celechron/utils/platform_features.dart';
import 'package:celechron/utils/utils.dart';

import 'allow_time_edit_page.dart';
import 'appearance_section.dart';
import 'course_id_mapping_edit_page.dart';
import 'credits_page.dart';
import 'custom_license_page.dart';
import 'diagnostic_log_page.dart';
import 'ecard_bill_page.dart';
import 'login_page.dart';
import 'network_proxy_page.dart';
import 'option_controller.dart';

class OptionPage extends StatelessWidget {
  final _optionController = Get.put(
    OptionController(),
    tag: 'optionController',
  );

  OptionPage({super.key});

  Text _trailingText(BuildContext context, String text, {Color? color}) {
    final colors = AelTheme.colorsOf(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? colors.textSecondary,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _footerNote(BuildContext context, String text) {
    final colors = AelTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: AelSpacing.sm, left: 4, right: 4),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);

    return CupertinoPageScaffold(
      backgroundColor: colors.pageBg,
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: AelLargeTitleBar(title: '设置', subtitle: '账号、外观、同步与工具配置'),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AelSpacing.pageHorizontal,
                AelSpacing.sm,
                AelSpacing.pageHorizontal,
                MediaQuery.paddingOf(context).bottom + 24,
              ),
              sliver: SliverList.list(
                children: [
                  _buildScholarSection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildPlannerSection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildCalendarSection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildBackupSection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildToolsSection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildNetworkSection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  const AppearanceSection(),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildDisplaySection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildDiagnosticsSection(context),
                  const SizedBox(height: AelSpacing.sectionGap),
                  _buildAboutSection(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScholarSection(BuildContext context) {
    return Obx(() {
      final colors = AelTheme.colorsOf(context);
      final isLoggedIn = _optionController.scholar.value.isLogan;
      final hasPush =
          (_optionController.pushOnGradeChange ||
              _optionController.pushOnDdlReminder ||
              _optionController.pushOnExamReminder) &&
          isLoggedIn;

      return AelSectionCard(
        title: '教务',
        icon: AelIcons.award,
        trailing: AelChip(
          label: isLoggedIn ? '已登录' : '未登录',
          tone: isLoggedIn ? AelChipTone.success : AelChipTone.neutral,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isLoggedIn) ...[
              AelListRow(
                title: '已登录: ${_optionController.scholar.value.username}',
                icon: AelIcons.shield,
                iconBgColor: colors.primaryContainer,
                iconColor: colors.onPrimaryContainer,
                trailing: Text(
                  '退出',
                  style: TextStyle(
                    color: colors.error,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => _confirmLogout(context),
              ),
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: ShapeDecoration(
                  color: colors.tonalTileBg,
                  shape: AelShapes.squircle(AelRadius.tile),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '重修绩点计算',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AelSegmented<GpaStrategy>(
                        stackedIcon: false,
                        items: const [
                          AelSegmentItem(
                            value: GpaStrategy.first,
                            label: '取首次',
                          ),
                          AelSegmentItem(value: GpaStrategy.best, label: '取最高'),
                        ],
                        value: _optionController.gpaStrategy,
                        onChanged: (value) {
                          _optionController.gpaStrategy = value;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Obx(
                () => AelSwitchTile(
                  title: '隐藏绩点',
                  icon: AelIcons.shield,
                  useTonalContainer: true,
                  value: _optionController.hideHomeGpa,
                  onChanged: (value) {
                    _optionController.hideHomeGpa = value;
                  },
                ),
              ),
              const SizedBox(height: 6),
              AelListRow(
                title: '自定义课程代码映射',
                icon: AelIcons.edit,
                onTap: () async {
                  Navigator.of(context, rootNavigator: true).push(
                    CupertinoPageRoute(
                      builder: (context) => CourseIdMappingEditPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              Obx(
                () => AelSwitchTile(
                  title: '异步刷新',
                  icon: AelIcons.refresh,
                  useTonalContainer: true,
                  value: _optionController.asyncRefresh,
                  onChanged: (value) {
                    _optionController.asyncRefresh = value;
                  },
                ),
              ),
              const SizedBox(height: 6),
              AelSwitchTile(
                title: '推送成绩变动',
                icon: AelIcons.bell,
                useTonalContainer: true,
                value: _optionController.pushOnGradeChange,
                onChanged: PlatformFeatures.hasBackgroundRefresh
                    ? (value) {
                        _optionController.pushOnGradeChange = value;
                      }
                    : null,
              ),
              const SizedBox(height: 6),
              AelSwitchTile(
                title: '推送作业截止提醒',
                icon: AelIcons.homework,
                useTonalContainer: true,
                value: _optionController.pushOnDdlReminder,
                onChanged: PlatformFeatures.hasBackgroundRefresh
                    ? (value) {
                        _optionController.pushOnDdlReminder = value;
                      }
                    : null,
              ),
              const SizedBox(height: 6),
              AelSwitchTile(
                title: '推送考前 1 小时提醒',
                subtitle: '考试开始前 1 小时发送座位号与物品清单通知',
                icon: AelIcons.exam,
                useTonalContainer: true,
                value: _optionController.pushOnExamReminder,
                onChanged: PlatformFeatures.hasBackgroundRefresh
                    ? (value) {
                        _optionController.pushOnExamReminder = value;
                      }
                    : null,
              ),
              if (hasPush)
                _footerNote(
                  context,
                  'Helechron 将不定期自动运行以刷新数据。请开启通知权限，且不要将 Helechron 从后台中移除。',
                ),
            ] else ...[
              AelListRow(
                title: '点击登录',
                subtitle: '绑定浙大通行证以同步课表、成绩与作业',
                icon: AelIcons.shield,
                iconBgColor: colors.primaryContainer,
                iconColor: colors.onPrimaryContainer,
                onTap: () {
                  showAelBottomSheet<void>(
                    context: context,
                    title: '统一身份认证登录',
                    subtitle: '绑定浙大通行证以同步课表、成绩与作业',
                    showCloseButton: true,
                    builder: (_) => LoginForm(),
                  );
                },
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildPlannerSection(BuildContext context) {
    return AelSectionCard(
      title: '时间规划',
      icon: AelIcons.activity,
      child: Column(
        children: [
          AelListRow(
            title: '工作段时间长度',
            icon: AelIcons.activity,
            trailing: Obx(
              () => _trailingText(
                context,
                durationToString(_optionController.workTime),
              ),
            ),
            onTap: () => _showWorkTimePicker(context),
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: '休息段时间长度',
            icon: AelIcons.sun,
            trailing: Obx(
              () => _trailingText(
                context,
                durationToString(_optionController.restTime),
              ),
            ),
            onTap: () => _showRestTimePicker(context),
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: '可用的工作时段',
            icon: AelIcons.tabFlow,
            trailing: Obx(
              () => _trailingText(
                context,
                '${_optionController.allowTimeLength} 个时段',
              ),
            ),
            onTap: () async {
              await Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => const AllowTimeEditPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarSection(BuildContext context) {
    return Obx(() {
      final colors = AelTheme.colorsOf(context);
      final syncEnabled = _optionController.calendarSyncEnabled.value;

      return AelSectionCard(
        title: '日程',
        icon: AelIcons.tabCalendar,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AelListRow(
              title: '同步到系统日历',
              icon: AelIcons.tabCalendar,
              showChevron: false,
              trailing: CupertinoAsyncSwitch(
                value:
                    syncEnabled &&
                    _optionController.hasCalendarPermission.value,
                onChanged: (value) async {
                  await _optionController.toggleCalendarSync(context, value);
                },
              ),
            ),
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.tonalTileBg,
                shape: AelShapes.squircle(AelRadius.tile),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '提醒方式',
                      style: TextStyle(
                        color: syncEnabled
                            ? colors.textPrimary
                            : colors.textTertiary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    IgnorePointer(
                      ignoring: !syncEnabled,
                      child: Opacity(
                        opacity: syncEnabled ? 1 : 0.45,
                        child: AelSegmented<CalendarReminderMode>(
                          stackedIcon: false,
                          items: const [
                            AelSegmentItem(
                              value: CalendarReminderMode.notification,
                              label: '通知提醒',
                            ),
                            AelSegmentItem(
                              value: CalendarReminderMode.alarm,
                              label: '闹钟提醒',
                            ),
                          ],
                          value: _optionController.calendarReminderMode,
                          onChanged: (value) {
                            _optionController.setCalendarReminderMode(value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Opacity(
              opacity: syncEnabled ? 1 : 0.5,
              child: AelListRow(
                title: '课表同步选项',
                icon: AelIcons.filter,
                trailing: _trailingText(context, '选择学期'),
                onTap: syncEnabled
                    ? () {
                        _optionController.showCalendarSyncDialog(context);
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 6),
            AelListRow(
              title: '导出为iCal文件',
              icon: AelIcons.share,
              onTap: () => _optionController.showExportDialog(context),
            ),
            const SizedBox(height: 6),
            AelListRow(
              key: ValueKey(
                'import_ics_${_optionController.icsImportKey.value}',
              ),
              title: '导入日程文件',
              subtitle: '从 .ics 日历文件导入日程与 DDL',
              icon: AelIcons.upload,
              onTap: () => _optionController.importIcs(),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildBackupSection(BuildContext context) {
    return Obx(
      () => AelSectionCard(
        title: '备份与恢复',
        icon: AelIcons.layers,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AelListRow(
              key: ValueKey(
                'export_backup_${_optionController.backupActionKey.value}',
              ),
              title: '导出备份',
              subtitle: '生成 JSON 备份文件并分享保存',
              icon: AelIcons.share,
              onTap: () => _optionController.exportBackup(),
            ),
            const SizedBox(height: 6),
            AelListRow(
              key: ValueKey(
                'import_backup_${_optionController.backupActionKey.value}',
              ),
              title: '导入备份',
              subtitle: '从备份文件恢复，将覆盖当前数据',
              icon: AelIcons.download,
              onTap: () => _optionController.importBackup(),
            ),
            _footerNote(context, '备份包含学业数据、任务列表、课程号映射与提醒时段等配置，不含账号密码。'),
          ],
        ),
      ),
    );
  }

  Widget _buildToolsSection(BuildContext context) {
    return AelSectionCard(
      title: '工具',
      icon: AelIcons.qrCode,
      child: Column(
        children: [
          AelListRow(
            title: '付款码',
            icon: AelIcons.qrCode,
            onTap: () async {
              Navigator.of(
                context,
                rootNavigator: true,
              ).pushNamed('/ecardpaypage');
            },
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: '校园卡账单与消费统计',
            subtitle: '按月查看流水、餐饮/商超/水电分类消费占比',
            icon: AelIcons.wallet,
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(builder: (context) => const ECardBillPage()),
              );
            },
          ),
          const SizedBox(height: 6),
          Obx(() {
            final threshold = _optionController.ecardLowBalanceThreshold;
            final label = threshold <= 0
                ? '已关闭'
                : '¥${threshold.toStringAsFixed(threshold == threshold.roundToDouble() ? 0 : 1)}';
            return AelListRow(
              title: '付款码低余额预警阈值',
              subtitle: '付款码页与桌面大码低于该值时提醒充值',
              icon: AelIcons.warning,
              trailing: _trailingText(context, label),
              onTap: () => _showLowBalanceThresholdPicker(context),
            );
          }),
          const SizedBox(height: 6),
          Obx(() {
            final path = _optionController.downloadPath;
            final displayPath = path.isEmpty ? '应用默认目录' : path;
            return AelListRow(
              title: '课件下载保存路径',
              subtitle: displayPath,
              icon: AelIcons.folder,
              onTap: () => _showDownloadPathPicker(context),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNetworkSection(BuildContext context) {
    return AelSectionCard(
      title: '网络与环境',
      icon: AelIcons.wifi,
      child: AelListRow(
        title: '网络代理与校内直连',
        subtitle: '解决挂节点无法访问浙大、分流规则与连通性体检',
        icon: AelIcons.globe,
        onTap: () async {
          Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(builder: (context) => const NetworkProxyPage()),
          );
        },
      ),
    );
  }

  Widget _buildDisplaySection(BuildContext context) {
    return AelSectionCard(
      title: '显示',
      icon: AelIcons.smartphone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AelListRow(
            title: '暗色模式',
            icon: AelIcons.moon,
            trailing: Obx(
              () => _trailingText(
                context,
                _optionController.brightnessMode == BrightnessMode.system
                    ? '跟随系统设置'
                    : _optionController.brightnessMode == BrightnessMode.light
                    ? '亮色模式'
                    : '暗色模式',
              ),
            ),
            onTap: () => _showBrightnessPicker(context),
          ),
          const SizedBox(height: 6),
          Obx(
            () => AelSwitchTile(
              title: '悬浮底栏',
              subtitle: '底部 Tab 栏悬停显示，胶囊形悬浮',
              icon: AelIcons.layers,
              useTonalContainer: true,
              value: _optionController.bottomBarFloating,
              onChanged: (value) {
                _optionController.bottomBarFloating = value;
              },
            ),
          ),
          const SizedBox(height: 6),
          Obx(
            () => AelSwitchTile(
              title: '沉浸光感',
              subtitle: '悬浮底栏背景液态玻璃光感效果',
              icon: AelIcons.sparkles,
              useTonalContainer: true,
              value: _optionController.bottomBarImmersiveLight,
              onChanged: _optionController.bottomBarFloating
                  ? (value) {
                      _optionController.bottomBarImmersiveLight = value;
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Obx(
            () => Opacity(
              opacity: _optionController.bottomBarImmersiveLight ? 1 : 0.5,
              child: AelListRow(
                title: '光感强度',
                subtitle: '跟随系统策略，或手动指定材质精细度',
                icon: AelIcons.contrast,
                trailing: _trailingText(
                  context,
                  _materialLevelName(_optionController.bottomBarMaterialLevel),
                ),
                onTap: _optionController.bottomBarImmersiveLight
                    ? () => _showMaterialLevelPicker(context)
                    : null,
              ),
            ),
          ),
          _footerNote(context, '悬浮底栏遵循鸿蒙原生设计规范，液态玻璃沉浸光感需要 HarmonyOS 6 及以上版本。'),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsSection(BuildContext context) {
    return AelSectionCard(
      title: '诊断与测试',
      icon: AelIcons.info,
      child: AelListRow(
        title: '测试日志',
        subtitle: '查看、复制或导出脱敏 TXT',
        icon: AelIcons.file,
        onTap: () {
          Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute(
              builder: (context) => DiagnosticLogPage(
                version: _optionController.celechronVersion,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return AelSectionCard(
      title: '关于',
      icon: AelIcons.info,
      child: Column(
        children: [
          if (PlatformFeatures.isAndroid) ...[
            AelListRow(
              title: '检查更新',
              subtitle: '支持应用内下载并自动调起安装',
              icon: AelIcons.download,
              trailing: _trailingText(
                context,
                'v${_optionController.celechronVersion}',
              ),
              onTap: () => _optionController.manualCheckUpdate(context),
            ),
            const SizedBox(height: 6),
            Obx(
              () => AelSwitchTile(
                title: '启动时自动检查更新',
                icon: AelIcons.refresh,
                useTonalContainer: true,
                value: _optionController.autoCheckUpdate.value,
                onChanged: (value) =>
                    _optionController.toggleAutoCheckUpdate(value),
              ),
            ),
            const SizedBox(height: 6),
          ],
          AelListRow(
            title: '关于 Helechron',
            icon: AelIcons.info,
            trailing: _trailingText(
              context,
              _optionController.celechronVersion,
            ),
            onTap: () async {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) =>
                      CreditsPage(version: _optionController.celechronVersion),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: '隐私政策',
            icon: AelIcons.shield,
            onTap: () async {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => const LegalDocumentPage(
                    title: '隐私政策',
                    assetPath: 'assets/legal/privacy_policy.txt',
                    onlineUrl: privacyPolicyUrl,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: '用户协议',
            icon: AelIcons.file,
            onTap: () async {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => const LegalDocumentPage(
                    title: '用户协议',
                    assetPath: 'assets/legal/user_agreement.txt',
                    onlineUrl: userAgreementUrl,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: 'ICP 备案号',
            icon: AelIcons.globe,
            showChevron: false,
            trailing: _trailingText(context, icpFilingNumber),
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: '开源许可证',
            icon: AelIcons.book,
            onTap: () async {
              Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute(
                  builder: (context) => const CustomLicensePage(),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          AelListRow(
            title: 'Helechron项目网站',
            icon: AelIcons.externalLink,
            onTap: () async {
              await launchUrlString(
                projectUrl,
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showAelConfirmDialog(
      context: context,
      title: '退出登录',
      message: '确定要退出当前账号吗？',
      confirmLabel: '退出',
      isDestructive: true,
    );
    if (confirmed) {
      await _optionController.logout();
    }
  }

  Future<void> _showWorkTimePicker(BuildContext context) async {
    Duration newWorkTime = _optionController.workTime;
    final confirmed = await showAelPickerSheet<Duration>(
      context: context,
      title: '工作段时间长度',
      pickerBuilder: (_) => CupertinoTimerPicker(
        mode: CupertinoTimerPickerMode.hm,
        minuteInterval: 5,
        initialTimerDuration: newWorkTime,
        onTimerDurationChanged: (value) {
          newWorkTime = value >= const Duration(minutes: 5)
              ? value
              : const Duration(minutes: 5);
        },
      ),
      onConfirm: () => newWorkTime,
    );
    if (confirmed != null) {
      _optionController.workTime = confirmed;
    }
  }

  Future<void> _showRestTimePicker(BuildContext context) async {
    Duration newRestTime = _optionController.restTime;
    final confirmed = await showAelPickerSheet<Duration>(
      context: context,
      title: '休息段时间长度',
      pickerBuilder: (_) => CupertinoTimerPicker(
        mode: CupertinoTimerPickerMode.hm,
        initialTimerDuration: newRestTime,
        onTimerDurationChanged: (value) {
          newRestTime = value;
        },
      ),
      onConfirm: () => newRestTime,
    );
    if (confirmed != null) {
      _optionController.restTime = confirmed;
    }
  }

  String _materialLevelName(int level) {
    switch (level) {
      case 0:
        return '精致';
      case 1:
        return '柔和';
      case 2:
        return '流畅';
      default:
        return '跟随系统';
    }
  }

  void _showMaterialLevelPicker(BuildContext context) {
    const levels = <int, String>{10: '跟随系统', 0: '精致', 1: '柔和', 2: '流畅'};
    final current = _optionController.bottomBarMaterialLevel;
    showAelActionSheet<int>(
      context: context,
      title: '选择底栏光感强度',
      actions: levels.entries
          .map(
            (entry) => AelActionOption<int>(
              value: entry.key,
              label: entry.value,
              isSelected: current == entry.key,
              onTap: () => _optionController.bottomBarMaterialLevel = entry.key,
            ),
          )
          .toList(),
    );
  }

  void _showBrightnessPicker(BuildContext context) {
    final current = _optionController.brightnessMode;
    showAelActionSheet<BrightnessMode>(
      context: context,
      title: '选择外观模式',
      actions: [
        AelActionOption<BrightnessMode>(
          value: BrightnessMode.system,
          label: '跟随系统设置',
          icon: AelIcons.smartphone,
          isSelected: current == BrightnessMode.system,
          onTap: () => _optionController.brightnessMode = BrightnessMode.system,
        ),
        AelActionOption<BrightnessMode>(
          value: BrightnessMode.light,
          label: '亮色模式',
          icon: AelIcons.sun,
          isSelected: current == BrightnessMode.light,
          onTap: () => _optionController.brightnessMode = BrightnessMode.light,
        ),
        AelActionOption<BrightnessMode>(
          value: BrightnessMode.dark,
          label: '暗色模式',
          icon: AelIcons.moon,
          isSelected: current == BrightnessMode.dark,
          onTap: () => _optionController.brightnessMode = BrightnessMode.dark,
        ),
      ],
    );
  }

  void _showLowBalanceThresholdPicker(BuildContext context) {
    final presets = <double, String>{
      0: '关闭低余额预警',
      10: '¥10',
      15: '¥15（默认）',
      20: '¥20',
      30: '¥30',
      50: '¥50',
    };
    final current = _optionController.ecardLowBalanceThreshold;
    showAelActionSheet<double>(
      context: context,
      title: '付款码低余额预警阈值',
      message: '当校园卡余额低于设定金额时，在付款码页及桌面大码页显示充值提醒',
      actions: [
        ...presets.entries.map(
          (entry) => AelActionOption<double>(
            value: entry.key,
            label: entry.value,
            isSelected: current == entry.key,
            onTap: () => _optionController.ecardLowBalanceThreshold = entry.key,
          ),
        ),
        AelActionOption<double>(
          label: '自定义金额...',
          icon: AelIcons.edit,
          isSelected: !presets.containsKey(current),
          onTap: () => _showCustomThresholdDialog(context),
        ),
      ],
    );
  }

  void _showCustomThresholdDialog(BuildContext context) {
    showAelInputDialog(
      context: context,
      title: '自定义低余额预警阈值（元）',
      initialValue: _optionController.ecardLowBalanceThreshold > 0
          ? _optionController.ecardLowBalanceThreshold.toStringAsFixed(0)
          : '15',
      placeholder: '输入金额（0 表示关闭）',
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (raw) {
        final val = double.tryParse(raw.trim());
        if (val == null || val < 0) {
          return '请输入不小于 0 的有效数字';
        }
        return null;
      },
    ).then((result) {
      if (result == null) return;
      final val = double.tryParse(result.trim());
      if (val != null && val >= 0) {
        _optionController.ecardLowBalanceThreshold = val;
      }
    });
  }

  void _showDownloadPathPicker(BuildContext context) {
    showAelActionSheet<void>(
      context: context,
      title: '课件下载保存路径',
      message: _optionController.downloadPath.isEmpty
          ? '当前：应用默认课件目录（支持直接唤起系统“打开方式”）'
          : '当前：${_optionController.downloadPath}',
      actions: [
        AelActionOption<void>(
          label: '通过系统选择器选择文件夹',
          icon: AelIcons.folder,
          onTap: () async {
            // 等待底部弹窗收起动画完成，避免 iOS/HarmonyOS 原生选择器弹出时机冲突
            await Future<void>.delayed(const Duration(milliseconds: 220));
            final picked = await OhosNativeService.instance.pickDirectory();
            if (picked != null && picked.isNotEmpty) {
              _optionController.downloadPath = picked;
              return;
            }
            final err = OhosNativeService.instance.lastFilePickError;
            if (err != null && err.isNotEmpty && context.mounted) {
              await showAelAlertDialog(
                context: context,
                title: '无法打开系统文件夹选择器',
                message: err,
                confirmLabel: '好',
              );
            }
          },
        ),
        AelActionOption<void>(
          label: '手动输入保存路径...',
          icon: AelIcons.edit,
          onTap: () => _showCustomDownloadPathDialog(context),
        ),
        if (_optionController.downloadPath.isNotEmpty)
          AelActionOption<void>(
            label: '恢复应用默认目录',
            icon: AelIcons.refresh,
            isDestructive: true,
            onTap: () => _optionController.downloadPath = '',
          ),
      ],
    );
  }

  void _showCustomDownloadPathDialog(BuildContext context) {
    showAelInputDialog(
      context: context,
      title: '设置课件下载目录',
      initialValue: _optionController.downloadPath,
      placeholder: '留空使用应用默认目录',
    ).then((result) {
      if (result != null) {
        _optionController.downloadPath = result.trim();
      }
    });
  }
}
