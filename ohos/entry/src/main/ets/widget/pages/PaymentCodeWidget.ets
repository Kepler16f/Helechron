let storagePaymentCode = new LocalStorage();

@Entry(storagePaymentCode)
@Component
struct PaymentCodeWidget {
  @LocalStorageProp('paymentCode') paymentCode: string = '';
  @LocalStorageProp('displayName') displayName: string = '浙大校园卡付款码';
  @LocalStorageProp('hasCode') hasCode: string = '0';

  build() {
    Column() {
      Row() {
        Text(this.displayName)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.widget_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.hasCode === '1' && this.paymentCode.length > 0) {
          Row() {
            Text('\u26F6')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.widget_button_text'))
          }
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor($r('app.color.widget_accent'))
          .justifyContent(FlexAlign.Center)
          .margin({ right: 6 })
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: {
                target: 'enlarged_qr',
                paymentCode: this.paymentCode
              }
            });
          })

          Row() {
            Text('\u21BB')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.widget_button_text'))
          }
          .width(28)
          .height(28)
          .borderRadius(14)
          .backgroundColor($r('app.color.widget_accent'))
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            postCardAction(this, {
              action: 'message',
              params: {
                event: 'refresh_payment_code'
              }
            });
          })
        }
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.hasCode === '1' && this.paymentCode.length > 0) {
        Column() {
          QRCode(this.paymentCode)
            .width('100%')
            .height('100%')
            .color('#000000')
            .backgroundColor($r('app.color.widget_qr_background'))
        }
        .layoutWeight(1)
        .aspectRatio(1)
        .alignSelf(ItemAlign.Center)
        .constraintSize({ maxWidth: '100%' })
        .padding(8)
        .backgroundColor($r('app.color.widget_qr_background'))
        .borderRadius(12)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: {
              target: 'ecardpaypage'
            }
          });
        })
      } else {
        Column({ space: 4 }) {
          Text('点击打开付款码')
            .fontSize(14)
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
    .padding(8)
    .backgroundColor($r('app.color.widget_background'))
    .borderRadius(16)
  }
}