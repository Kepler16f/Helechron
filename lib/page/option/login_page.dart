import 'package:celechron/utils/platform_features.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:celechron/design/components/ael_components.dart';
import 'package:celechron/design/icons/ael_icons.dart';
import 'package:celechron/design/tokens/ael_tokens.dart';
import 'package:celechron/model/scholar.dart';

import '../../worker/ecard_widget_messenger.dart';
import 'option_controller.dart';
import 'package:celechron/design/theme/ael_theme.dart';

class LoginForm extends StatelessWidget {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final _optionController = Get.find<OptionController>(tag: 'optionController');
  final buttonPressed = false.obs;

  LoginForm({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AelTheme.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 50,
          child: CupertinoTextField(
            controller: usernameController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colors.textPrimary, fontSize: 15.5),
            placeholderStyle: TextStyle(color: colors.textTertiary),
            placeholder: '请输入学号',
            prefix: Padding(
              padding: const EdgeInsets.only(left: AelSpacing.lg),
              child: Text(
                '学号',
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
        ),
        const SizedBox(height: AelSpacing.md),
        SizedBox(
          height: 50,
          child: CupertinoTextField(
            controller: passwordController,
            obscureText: true,
            style: TextStyle(color: colors.textPrimary, fontSize: 15.5),
            placeholderStyle: TextStyle(color: colors.textTertiary),
            placeholder: '请输入统一身份认证密码',
            prefix: Padding(
              padding: const EdgeInsets.only(left: AelSpacing.lg),
              child: Text(
                '密码',
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
        ),
        const SizedBox(height: AelSpacing.lg),
        Obx(
          () => AelButton(
            expanded: true,
            icon: buttonPressed.value ? null : AelIcons.check,
            label: buttonPressed.value ? '正在登录...' : '登录',
            onPressed: buttonPressed.value
                ? null
                : () async {
                    buttonPressed.value = true;
                    var scholar = Get.find<Rx<Scholar>>(tag: 'scholar');
                    scholar.update((val) {
                      val!.username = usernameController.value.text;
                      val.password = passwordController.value.text;
                      val.login().then((value) async {
                        if (value.every((e) => e == null)) {
                          await val.refresh(onPartialUpdate: scholar.refresh);
                          scholar.refresh();
                          buttonPressed.value = false;
                          _optionController.pushOnGradeChange =
                              PlatformFeatures.hasBackgroundRefresh;
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        } else {
                          buttonPressed.value = false;
                          if (!context.mounted) return;
                          showAelAlertDialog(
                            context: context,
                            title: '登录失败',
                            message: value
                                .where((e) => e != null)
                                .fold('', (p, v) => '$p\n$v')
                                .trim(),
                          );
                        }
                        ECardWidgetMessenger.update();
                      });
                    });
                  },
          ),
        ),
      ],
    );
  }
}
