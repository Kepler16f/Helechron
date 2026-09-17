let storagePaymentCode = new LocalStorage();

@Entry(storagePaymentCode)
@Component
struct PaymentCodeWidget {
  @LocalStorageProp('paymentCode') paymentCode: string = '';
  @LocalStorageProp('displayName') displayName: string = '浙大校园卡付款码';
  @LocalStorageProp('hasCode') hasCode: string = '0';

  build() {
    Column() {
      // 顶部标题
      Row() {
        Text(this.displayName)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.widget_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      // 主体内容
      if (this.hasCode === '1' && this.paymentCode.length > 0) {
        // 二维码区域：点击进入付款码页
        Column() {
          QRCode(this.paymentCode)
            .width('66%')
            .aspectRatio(1)
            .color('#000000')
            .backgroundColor($r('app.color.widget_qr_background'))
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

        // 刷新按钮（图标）：触发 onFormEvent 直接刷新卡片，不拉起应用
        Row() {
          Text('\u21BB')
            .fontSize(18)
            .fontColor($r('app.color.widget_accent'))
        }
        .width(40)
        .height(26)
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8, bottom: 2 })
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
    .padding(10)
    .backgroundColor($r('app.color.widget_background'))
    .borderRadius(16)
  }
}
