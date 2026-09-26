/// 桌面小组件点击放大按钮后，EnlargedQRAbility 启动时加载的页面。
/// 以弹窗样式渲染付款码大图 + 刷新按钮 + 关闭按钮，
/// 背景全透明并使用 ArkTS 原生 backgroundEffect 呈现高质感液态玻璃模糊，无灰色半透明蒙版。
/// 侧滑返回或点击关闭/背景均直接 terminateSelf() 退出回桌面，完全不涉及 Flutter 主页面。

import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { window } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';

const DOMAIN = 0x0000;
const TAG = 'HelechronEnlargedQR';
const PREFS_NAME = 'helechron_widget_data';
const FORM_IDS_KEY = 'payment_form_ids';
const TEST_ACCOUNT = '3200000000';
const BARCODE_URL_PREFIX =
  'https://elife.zju.edu.cn/berserker-app/ykt/tsm/batchGetBarCodeGet?account=';
const BARCODE_URL_SUFFIX = '&payacc=%23%23%23&paytype=1&synAccessSource=app';

@Entry
@Component
struct EnlargedQRPage {
  private context = getContext(this) as common.UIAbilityContext;
  @State private paymentCode: string = '';
  @State private isRefreshing: boolean = false;
  @State private refreshAngle: number = 0;

  aboutToAppear(): void {
    try {
      window.getLastWindow(this.context).then((mainWindow: window.Window) => {
        try {
          mainWindow.setWindowBackgroundColor('#00000000');
          mainWindow.setWindowLayoutFullScreen(true);
        } catch (e) {}
      }).catch(() => {});
    } catch (e) {}

    try {
      const fromStorage: string | undefined = AppStorage.get<string>('enlargedQrPaymentCode');
      if (typeof fromStorage === 'string' && fromStorage.length > 0) {
        this.paymentCode = fromStorage;
        return;
      }
      const prefs: preferences.Preferences = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      const stored: string = prefs.getSync('paymentCode', '') as string;
      if (stored.length > 0) {
        this.paymentCode = stored;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `read initial code failed: ${JSON.stringify(e)}`);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景模糊层：纯透明背景配合 ArkTS 原生 backgroundEffect，无半透明灰色遮罩，点击窗口外区域退出
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .backgroundEffect({
          radius: 60,
          saturation: 2.0,
          brightness: 1.05
        })
        .onClick(() => {
          this.close();
        })

      // 居中付款码卡片
      Column({ space: 16 }) {
        // 顶部标题与刷新按钮
        Row() {
          Text('付款码')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_text_primary'))

          Blank()

          // 刷新按钮：带单次 360 度旋转动画与原生取码
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_widget_refresh'))
              .width(16)
              .height(16)
              .fillColor(this.isRefreshing ? $r('app.color.widget_text_tertiary') : $r('app.color.widget_accent'))
              .rotate({ angle: this.refreshAngle })
          }
          .width(32)
          .height(32)
          .backgroundColor($r('app.color.widget_badge_background'))
          .enabled(!this.isRefreshing)
          .opacity(this.isRefreshing ? 0.6 : 1.0)
          .onClick(() => {
            this.refreshPaymentCode();
          })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 18 })

        if (this.paymentCode.length > 0) {
          Column() {
            QRCode(this.paymentCode)
              .width('100%')
              .height('100%')
              .color('#000000')
          }
          .width(260)
          .height(260)
          .padding(12)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .border({ width: 1, color: '#22000000' })

          Text(this.paymentCode)
            .fontSize(15)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Medium)
            .letterSpacing(1.2)
            .fontColor($r('app.color.widget_text_primary'))
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 16, right: 16 })
        } else {
          Text('暂无可用的付款码')
            .fontSize(14)
            .fontColor($r('app.color.widget_text_tertiary'))
            .margin({ top: 40, bottom: 40 })
        }

        Button('关闭')
          .width('72%')
          .height(40)
          .backgroundColor($r('app.color.widget_accent'))
          .fontColor(Color.White)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 20 })
          .onClick(() => {
            this.close();
          })
      }
      .width('84%')
      .constraintSize({ maxWidth: 360, maxHeight: 470 })
      .backgroundColor($r('app.color.widget_background'))
      .borderRadius(20)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  /// 刷新付款码：触发单次 360 度平滑旋转动画，网络请求完成后动画平滑减速停止
  private async refreshPaymentCode(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;

    // 单次 360 度平滑旋转，结束后重置 isRefreshing，支持下次重新触发
    animateTo({
      duration: 700,
      curve: Curve.EaseInOut,
      onFinish: () => {
        this.isRefreshing = false;
      }
    }, () => {
      this.refreshAngle += 360;
    });

    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      const auth: string = (prefs.getSync('synjonesAuth', '') as string) || '';
      const account: string = (prefs.getSync('eCardAccount', '') as string) || '';

      if (auth.length === 0) {
        hilog.warn(DOMAIN, TAG, 'refreshPaymentCode: no synjonesAuth in preferences');
        return;
      }

      let newCode: string = '';
      if (auth === TEST_ACCOUNT || account === TEST_ACCOUNT) {
        for (let i = 0; i < 16; i++) {
          newCode += Math.floor(Math.random() * 10).toString();
        }
      } else {
        const httpRequest: http.HttpRequest = http.createHttp();
        try {
          const url: string = `${BARCODE_URL_PREFIX}${account}${BARCODE_URL_SUFFIX}`;
          const header: Record<string, string> = { 'synjones-auth': `bearer ${auth}` };
          const options: http.HttpRequestOptions = {
            method: http.RequestMethod.GET,
            header: header,
            connectTimeout: 4000,
            readTimeout: 4000,
            expectDataType: http.HttpDataType.STRING
          };
          const response: http.HttpResponse = await httpRequest.request(url, options);
          if (response.responseCode === 200) {
            const text: string = response.result as string;
            const payload: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
            const data: Record<string, Object> = payload['data'] as Record<string, Object>;
            if (data !== undefined && data !== null) {
              const barcodes: string[] = data['barcode'] as string[];
              if (barcodes !== undefined && barcodes !== null && barcodes.length > 0) {
                newCode = barcodes[0];
              }
            }
          }
        } finally {
          httpRequest.destroy();
        }
      }

      if (newCode.length > 0) {
        this.paymentCode = newCode;
        AppStorage.setOrCreate('enlargedQrPaymentCode', newCode);
        prefs.putSync('paymentCode', newCode);
        prefs.flush();

        // 同步刷新所有已添加的桌面小组件
        const rawIds: string = prefs.getSync(FORM_IDS_KEY, '') as string;
        if (rawIds.length > 0) {
          const ids: string[] = rawIds.split(',').filter((id: string) => id.length > 0);
          const payData: Record<string, string> = {
            'paymentCode': newCode,
            'displayName': '付款码',
            'hasCode': '1'
          };
          const bindingData: formBindingData.FormBindingData = formBindingData.createFormBindingData(payData);
          for (const formId of ids) {
            formProvider.updateForm(formId, bindingData).catch((err: BusinessError) => {
              hilog.warn(DOMAIN, TAG, `updateForm failed for ${formId}: ${err.message}`);
            });
          }
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `refreshPaymentCode failed: ${JSON.stringify(e)}`);
    }
  }

  private close(): void {
    try {
      AppStorage.setOrCreate('enlargedQrPaymentCode', '');
    } catch (e) {}
    try {
      this.context.terminateSelf();
    } catch (e) {
      hilog.error(DOMAIN, TAG, `terminateSelf failed: ${JSON.stringify(e)}`);
    }
  }

  onBackPress(): boolean {
    this.close();
    return true;
  }
}