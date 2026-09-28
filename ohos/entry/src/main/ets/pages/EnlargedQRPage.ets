/// 桌面小组件点击放大按钮后，EnlargedQRAbility 启动时加载的页面。
/// 以弹窗样式渲染付款码大图 + 刷新按钮 + 关闭按钮，
/// 背景全透明并使用 ArkTS 原生 backgroundEffect 呈现高质感液态玻璃模糊，无灰色半透明蒙版。
/// 侧滑返回或点击关闭/背景均直接 terminateSelf() 退出回桌面，完全不涉及 Flutter 主页面。

import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { window, promptAction } from '@kit.ArkUI';
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
const USER_AGENT = 'E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)';

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

      // 居中付款码卡片（按标准比例适配卡片边距）
      Column({ space: 14 }) {
        // 顶部标题与刷新按钮
        Row() {
          Text('付款码')
            .fontSize(19)
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
        .padding({ left: 22, right: 22, top: 18 })

        if (this.paymentCode.length > 0) {
          // 二维码容器：标准 200x200 黄金比例（与参考界面严格保持约 62%-64% 页面/卡片宽比，留白呼吸感自然）
          Column() {
            QRCode(this.paymentCode)
              .width('100%')
              .height('100%')
              .color('#000000')
          }
          .width(200)
          .height(200)
          .padding(10)
          .backgroundColor(Color.White)
          .borderRadius(12)

          // 条码文本容器：参考付款码界面胶囊式展示，等宽字体防变形
          Row() {
            Text(this.paymentCode)
              .fontSize(15)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Medium)
              .letterSpacing(1.4)
              .fontColor($r('app.color.widget_text_primary'))
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.widget_badge_background'))
          .borderRadius(8)
        } else {
          Text('暂无可用的付款码')
            .fontSize(14)
            .fontColor($r('app.color.widget_text_tertiary'))
            .margin({ top: 32, bottom: 32 })
        }

        Button('关闭')
          .width('75%')
          .height(38)
          .backgroundColor($r('app.color.widget_accent'))
          .fontColor(Color.White)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 18 })
          .onClick(() => {
            this.close();
          })
      }
      .width('82%')
      .constraintSize({ maxWidth: 320, maxHeight: 450 })
      .backgroundColor($r('app.color.widget_background'))
      .borderRadius(18)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  /// 刷新付款码：集成重试与完整网络头，失败时弹出友好弹窗提示
  private async refreshPaymentCode(): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;

    // 单次 360 度平滑旋转动画
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
        this.showFailureDialog('未检测到校园卡登录态，请打开应用并在「设置 → 校园卡账户」中完成登录。');
        return;
      }

      let newCode: string = '';
      if (auth === TEST_ACCOUNT || account === TEST_ACCOUNT) {
        for (let i = 0; i < 16; i++) {
          newCode += Math.floor(Math.random() * 10).toString();
        }
      } else {
        newCode = await this.requestBarcodeWithRetry(account, auth);
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
      } else {
        this.showFailureDialog('获取付款码失败，请检查网络连接后重试。');
      }
    } catch (e) {
      const errStr: string = String(e);
      hilog.error(DOMAIN, TAG, `refreshPaymentCode failed: ${errStr}`);
      if (errStr.indexOf('AUTH_EXPIRED') >= 0) {
        this.showFailureDialog('校园卡登录态已过期，请打开应用重新登录校园卡。');
      } else {
        this.showFailureDialog('当前网络环境不稳定，刷新付款码超时。请检查网络信号后重试。');
      }
    }
  }

  /// 发起取码网络请求，支持防丢包自动重试与标准移动端请求头
  private async requestBarcodeWithRetry(account: string, auth: string): Promise<string> {
    const url: string = `${BARCODE_URL_PREFIX}${account}${BARCODE_URL_SUFFIX}`;
    const header: Record<string, string> = {
      'synjones-auth': `bearer ${auth}`,
      'User-Agent': USER_AGENT,
      'Accept': 'application/json, text/plain, */*',
      'Connection': 'keep-alive',
      'Cache-Control': 'no-cache'
    };

    let lastErrMsg: string = '';
    // 最多尝试 2 次，首次遇网络闪断或超时自动触发第二次重试
    for (let attempt = 1; attempt <= 2; attempt++) {
      const httpRequest: http.HttpRequest = http.createHttp();
      try {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: header,
          connectTimeout: 6000,
          readTimeout: 6500,
          expectDataType: http.HttpDataType.STRING
        };
        const response: http.HttpResponse = await httpRequest.request(url, options);
        if (response.responseCode === 200) {
          const text: string = response.result as string;
          const payload: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
          const codeVal: Object = payload['code'];
          if (codeVal === 401 || codeVal === '401' || payload['msg'] === 'token invalid') {
            throw new Error('AUTH_EXPIRED');
          }
          const data: Record<string, Object> = payload['data'] as Record<string, Object>;
          if (data !== undefined && data !== null) {
            const barcodes: string[] = data['barcode'] as string[];
            if (barcodes !== undefined && barcodes !== null && barcodes.length > 0) {
              const rawCode: string = barcodes[0];
              // 合法性校验
              if (rawCode.length >= 14 && rawCode.length <= 64) {
                return rawCode;
              }
            }
          }
          lastErrMsg = '未获取到有效付款码数据';
        } else if (response.responseCode === 401 || response.responseCode === 403) {
          throw new Error('AUTH_EXPIRED');
        } else {
          lastErrMsg = `服务器返回状态码 HTTP ${response.responseCode}`;
        }
      } catch (err) {
        const errStr: string = String(err);
        if (errStr.indexOf('AUTH_EXPIRED') >= 0) {
          throw err;
        }
        lastErrMsg = '网络连接超时';
        hilog.warn(DOMAIN, TAG, `requestBarcode attempt ${attempt} failed: ${errStr}`);
      } finally {
        httpRequest.destroy();
      }

      if (attempt < 2) {
        await new Promise<void>((resolve) => setTimeout(resolve, 300));
      }
    }

    throw new Error(lastErrMsg.length > 0 ? lastErrMsg : '网络连接失败');
  }

  /// 弹窗提示刷新失败原因
  private showFailureDialog(message: string): void {
    try {
      promptAction.showDialog({
        title: '付款码刷新失败',
        message: message,
        buttons: [
          {
            text: '我知道了',
            color: '#0A59F7'
          }
        ]
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `showDialog failed: ${JSON.stringify(err)}`);
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `showFailureDialog exception: ${JSON.stringify(e)}`);
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