/// 桌面小组件点击放大按钮后，EnlargedQRAbility 启动时加载的页面。
/// 以弹窗样式渲染付款码大图 + 自动刷新 + 墓碑后台原生重登取码 + 高亮度护航，
/// 二维码物理尺寸（160vp 码体 + 22vp 四周纯白静区）与垂直位置（约屏幕高度 52%）严格对齐学校电子校园卡。

import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { window, promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { ECardNativeHelper } from '../widget/ECardNativeHelper';

const DOMAIN = 0x0000;
const TAG = 'HelechronEnlargedQR';

@Entry
@Component
struct EnlargedQRPage {
  private context = getContext(this) as common.UIAbilityContext;
  @State private paymentCode: string = '';
  @State private isRefreshing: boolean = false;
  @State private refreshAngle: number = 0;
  @State private statusHint: string = '每分钟自动刷新，或点击二维码手动刷新';
  @StorageLink('enlargedQrOpenSeq') @Watch('onOpenSeqChanged') openSeq: number = 0;
  private autoRefreshTimerId: number = -1;

  aboutToAppear(): void {
    this.setupWindowForScanning();
    this.loadCachedCode();
    // 每次打开放大窗立即自动刷新一次付款码，无需用户再手动点击刷新按钮
    this.refreshPaymentCode(true);
    this.startAutoRefreshLoop();
  }

  aboutToDisappear(): void {
    this.stopAutoRefreshLoop();
  }

  onOpenSeqChanged(): void {
    this.setupWindowForScanning();
    this.loadCachedCode();
    this.refreshPaymentCode(true);
    this.startAutoRefreshLoop();
  }

  private setupWindowForScanning(): void {
    try {
      window.getLastWindow(this.context).then((mainWindow: window.Window) => {
        try {
          mainWindow.setWindowBackgroundColor('#00000000');
          mainWindow.setWindowLayoutFullScreen(true);
        } catch (e) {}
      }).catch(() => {});
    } catch (e) {}
  }

  private loadCachedCode(): void {
    try {
      const fromStorage: string | undefined = AppStorage.get<string>('enlargedQrPaymentCode');
      if (typeof fromStorage === 'string' && fromStorage.length > 0) {
        this.paymentCode = fromStorage;
        return;
      }
      const prefs = ECardNativeHelper.getFreshPrefs(this.context);
      if (prefs !== null) {
        const stored: string = (prefs.getSync('paymentCode', '') as string) || '';
        if (stored.length > 0) {
          this.paymentCode = stored;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `read initial code failed: ${JSON.stringify(e)}`);
    }
  }

  private startAutoRefreshLoop(): void {
    this.stopAutoRefreshLoop();
    this.autoRefreshTimerId = setInterval(() => {
      this.refreshPaymentCode(true);
    }, 55000);
  }

  private stopAutoRefreshLoop(): void {
    if (this.autoRefreshTimerId !== -1) {
      clearInterval(this.autoRefreshTimerId);
      this.autoRefreshTimerId = -1;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景模糊层：纯透明背景配合 ArkTS 原生 backgroundEffect，点击窗口外区域退出
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

      // 付款码卡片：整体向下微移 24vp，使二维码中心点精确处于屏幕高度 ~52%（对齐官方电子校园卡黄金扫码位）
      Column({ space: 12 }) {
        // 顶部标题与刷新按钮
        Row() {
          Text('付款码')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_text_primary'))

          Blank()

          // 刷新按钮：带单次 360 度旋转动画与原生取码（含墓碑后台自动重登）
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
            this.refreshPaymentCode(false);
          })
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 20, bottom: 4 })

        if (this.paymentCode.length > 0) {
          // 二维码容器：严格对齐官方电子校园卡比例
          // 160x160vp 码体（约占屏宽 42%）+ 四周 22vp 超宽纯白静区（总白底 204x204vp），
          // 防止近距离贴靠校内刷卡机扫码窗时边角超出镜头视场或畸变；点击二维码可直接刷新。
          Column() {
            QRCode(this.paymentCode)
              .width(160)
              .height(160)
              .color('#000000')
              .backgroundColor(Color.White)
          }
          .width(204)
          .height(204)
          .padding(22)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .border({ width: 1.5, color: '#260A59F7' })
          .onClick(() => {
            this.refreshPaymentCode(false);
          })

          Text(this.statusHint)
            .fontSize(11)
            .fontColor(this.isRefreshing ? $r('app.color.widget_accent') : $r('app.color.widget_text_tertiary'))
            .textAlign(TextAlign.Center)
            .maxLines(1)

          // 条码文本容器：胶囊式等宽数字展示
          Row() {
            Text(this.paymentCode)
              .fontSize(14)
              .fontFamily('monospace')
              .fontWeight(FontWeight.Medium)
              .letterSpacing(1.3)
              .fontColor($r('app.color.widget_text_primary'))
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding({ left: 14, right: 14, top: 5, bottom: 5 })
          .backgroundColor($r('app.color.widget_badge_background'))
          .borderRadius(8)
        } else {
          Column({ space: 8 }) {
            Text(this.isRefreshing ? '正在刷新付款码...' : '暂无可用的付款码')
              .fontSize(14)
              .fontColor($r('app.color.widget_text_tertiary'))
          }
          .margin({ top: 48, bottom: 48 })
        }

        Button('关闭')
          .width('75%')
          .height(38)
          .backgroundColor($r('app.color.widget_accent'))
          .fontColor(Color.White)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 2, bottom: 18 })
          .onClick(() => {
            this.close();
          })
      }
      .width('82%')
      .constraintSize({ maxWidth: 320, maxHeight: 460 })
      .backgroundColor($r('app.color.widget_background'))
      .borderRadius(18)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Center)
      .offset({ x: 0, y: 24 })
    }
    .width('100%')
    .height('100%')
  }

  /// 刷新付款码：支持打开时自动刷新（isAuto=true）与手动点击刷新（isAuto=false）。
  /// 当主应用在后台被杀或处于墓碑后台导致 synjonesAuth 过期时，自动由 ECardNativeHelper 完成原生重登与取码。
  private async refreshPaymentCode(isAuto: boolean): Promise<void> {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    this.statusHint = '正在刷新付款码...';

    // 单次 360 度平滑旋转动画
    animateTo({
      duration: 700,
      curve: Curve.EaseInOut,
      onFinish: () => {}
    }, () => {
      this.refreshAngle += 360;
    });

    try {
      const res = await ECardNativeHelper.fetchBarcodeWithAutoRelogin(this.context);
      if (res.code.length > 0) {
        this.paymentCode = res.code;
        AppStorage.setOrCreate('enlargedQrPaymentCode', res.code);
        this.statusHint = '已更新 · 每分钟自动刷新，或点击二维码手动刷新';
      } else {
        this.statusHint = '点击二维码或右上角按钮重试刷新';
        if (isAuto && this.paymentCode.length > 0) {
          // 自动刷新失败但已有码展示时，使用轻提示避免阻断用户扫码操作
          try {
            promptAction.showToast({
              message: res.errorMessage.length > 0 ? res.errorMessage : '自动刷新暂未成功，可点击二维码重试',
              duration: 2500
            });
          } catch (e) {}
        } else {
          this.showFailureDialog(
            res.errorMessage.length > 0
              ? res.errorMessage
              : '获取付款码失败，请检查网络连接后重试。'
          );
        }
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `refreshPaymentCode unexpected error: ${String(e)}`);
      this.statusHint = '点击二维码或右上角按钮重试刷新';
      if (!isAuto || this.paymentCode.length === 0) {
        this.showFailureDialog('当前网络环境不稳定，刷新付款码超时。请检查网络信号后重试。');
      }
    } finally {
      this.isRefreshing = false;
    }
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
    this.stopAutoRefreshLoop();
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
