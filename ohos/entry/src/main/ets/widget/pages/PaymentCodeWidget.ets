let storagePaymentCode = new LocalStorage();

@Entry(storagePaymentCode)
@Component
struct PaymentCodeWidget {
  @LocalStorageProp('paymentCode') paymentCode: string = '';
  @LocalStorageProp('displayName') displayName: string = '浙大校园卡付款码';
  @LocalStorageProp('hasCode') hasCode: string = '0';

  build() {
    Column() {
      // 顶部标题：放大并居中
      Text(this.displayName)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.widget_text_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 主体内容
      if (this.hasCode === '1' && this.paymentCode.length > 0) {
        // 二维码：按剩余高度取正方形，确保与刷新按钮不重叠
        QRCode(this.paymentCode)
          .layoutWeight(1)
          .aspectRatio(1)
          .color('#000000')
          .backgroundColor($r('app.color.widget_qr_background'))
          .margin({ top: 6, bottom: 6 })
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: {
                target: 'ecardpaypage'
              }
            });
          })

        // 刷新按钮：实心圆形按钮，点击后原生侧直接重新取码（不拉起应用）
        Row() {
          Text('\u21BB')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.widget_button_text'))
        }
        .width(36)
        .height(32)
        .borderRadius(16)
        .backgroundColor($r('app.color.widget_accent'))
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 2 })
        .onClick(() => {
          postCardAction(this, {
            action: 'message',
            params: {
              event: 'refresh_payment_code'
            }
          });
        })
      } else {
        Column({ space: 4 }) {
          Text('点击打开付款码')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.widget_accent'))

          Text('打开应用后自动同步')
            .fontSize(10)
            .fontColor($r('app.color.widget_text_tertiary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: {
              target: 'ecardpaypage'
            }
          });
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.widget_background'))
    .borderRadius(16)
  }
}
