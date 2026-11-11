import 'package:flutter/cupertino.dart';
import 'package:celechron/page/scholar/curriculum_plan/curriculum_plan_page.dart';

export 'package:celechron/page/scholar/curriculum_plan/curriculum_plan_page.dart';

/// 向下兼容别名包装类（已重构升级为 CurriculumPlanPage 培养方案查看）
class CreditProgressPage extends StatelessWidget {
  CreditProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CurriculumPlanPage();
  }
}
