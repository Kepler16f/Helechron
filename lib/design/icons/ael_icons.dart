import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 统一图标出口（基于 Lucide 线性图标库，保证线宽与视觉语言一致）。
///
/// 后续重构后的业务页面一律通过 [AelIcons] 引用图标，禁止直接使用
/// `Icons.*` 或 `CupertinoIcons.*`。
final class AelIcons {
  const AelIcons._();

  // 底部 5 个主导航 Tab
  static const IconData tabFlow = LucideIcons.clock3;
  static const IconData tabCalendar = LucideIcons.calendarDays;
  static const IconData tabTask = LucideIcons.circleCheck;
  static const IconData tabScholar = LucideIcons.graduationCap;
  static const IconData tabOption = LucideIcons.settings;

  // 通用操作与导航
  static const IconData back = LucideIcons.chevronLeft;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData close = LucideIcons.x;
  static const IconData add = LucideIcons.plus;
  static const IconData edit = LucideIcons.pencil;
  static const IconData delete = LucideIcons.trash2;
  static const IconData copy = LucideIcons.copy;
  static const IconData share = LucideIcons.share2;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData search = LucideIcons.search;
  static const IconData filter = LucideIcons.slidersHorizontal;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData check = LucideIcons.check;
  static const IconData externalLink = LucideIcons.externalLink;
  static const IconData download = LucideIcons.download;
  static const IconData upload = LucideIcons.upload;
  static const IconData folder = LucideIcons.folder;
  static const IconData file = LucideIcons.fileText;

  // 主题与外观
  static const IconData palette = LucideIcons.palette;
  static const IconData sparkles = LucideIcons.sparkles;
  static const IconData sun = LucideIcons.sun;
  static const IconData moon = LucideIcons.moon;
  static const IconData contrast = LucideIcons.contrast;
  static const IconData smartphone = LucideIcons.smartphone;
  static const IconData layers = LucideIcons.layers;

  // 状态与提示
  static const IconData info = LucideIcons.info;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData error = LucideIcons.circleAlert;
  static const IconData success = LucideIcons.circleCheckBig;
  static const IconData shield = LucideIcons.shieldCheck;
  static const IconData bell = LucideIcons.bell;
  static const IconData bellOff = LucideIcons.bellOff;

  // 校园与业务语义
  static const IconData book = LucideIcons.bookOpen;
  static const IconData award = LucideIcons.award;
  static const IconData exam = LucideIcons.clipboardList;
  static const IconData homework = LucideIcons.filePenLine;
  static const IconData video = LucideIcons.play;
  static const IconData qrCode = LucideIcons.qrCode;
  static const IconData wallet = LucideIcons.wallet;
  static const IconData wifi = LucideIcons.wifi;
  static const IconData globe = LucideIcons.globe;
  static const IconData activity = LucideIcons.activity;
  static const IconData location = LucideIcons.mapPin;
  static const IconData teacher = LucideIcons.user;
}
