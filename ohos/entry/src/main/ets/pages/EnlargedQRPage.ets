/// 桌面小组件点击放大按钮后，EntryAbility 启动时优先加载的页面。
/// 以"窗口/卡片"样式渲染付款码大图 + 关闭按钮（不占满全屏，四周留白透明），
/// 关闭后 terminateSelf() 退出应用，不进入 Flutter 主页。

import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'HelechronEnlargedQR';

@Entry
@Component
struct EnlargedQRPage {
  private context = getContext(this) as common.UIAbilityContext;
  @State private paymentCode: string = '';

  aboutToAppear(): void {
    // 码值由 EntryAbility 在冷启动阶段（captureRouteFromWant）写入 AppStorage
    try {
      const fromStorage = AppStorage.get<string>('enlargedQrPaymentCode');
      if (typeof fromStorage === 'string' && fromStorage.length > 0) {
        this.paymentCode = fromStorage;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `read AppStorage failed: ${JSON.stringify(e)}`);
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 背景模糊层：把桌面壁纸模糊化，点窗口外关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundEffect({
          radius: 60,
          saturation: 1.6,
          brightness: 1.0
        })
        .onClick(() => {
          this.close();
        })

      // 居中卡片
      Column({ space: 20 }) {
        Text('付款码')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.widget_text_primary'))
          .margin({ top: 20 })

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
          .width('70%')
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
      .width('82%')
      .constraintSize({ maxWidth: 360, maxHeight: 460 })
      .backgroundColor($r('app.color.widget_background'))
      .borderRadius(20)
      .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  private close(): void {
    try {
      AppStorage.setOrCreate('enlargedQrPaymentCode', '');
    } catch (e) {
      // ignore
    }
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