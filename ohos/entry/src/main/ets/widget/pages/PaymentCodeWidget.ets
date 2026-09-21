let storagePaymentCode = new LocalStorage();

@CustomDialog
struct EnlargedCodeDialog {
  controller: CustomDialogController;
  @LocalStorageProp('paymentCode') paymentCode: string = '';

  build() {
    Column({ space: 20 }) {
      Text('付款码')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#000000')
        .margin({ top: 24 })

      Column() {
        QRCode(this.paymentCode)
          .width('100%')
          .height('100%')
          .color('#000000')
      }
      .width(280)
      .height(280)
      .padding(12)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .border({ width: 1, color: '#22000000' })

      Text(this.paymentCode)
        .fontSize(18)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Medium)
        .letterSpacing(1.5)
        .fontColor('#000000')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 16, right: 16 })

      Button('关闭')
        .width('60%')
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#0A59F7')
        .onClick(() => {
          this.controller.close();
        })
        .margin({ bottom: 24 })
    }
    .width('90%')
    .backgroundColor(Color.White)
    .borderRadius(20)
    .padding({ left: 16, right: 16 })
  }
}

@Entry(storagePaymentCode)
@Component
struct PaymentCodeWidget {
  @LocalStorageProp('paymentCode') paymentCode: string = '';
  @LocalStorageProp('displayName') displayName: string = '浙大校园卡付款码';
  @LocalStorageProp('hasCode') hasCode: string = '0';

  dialogController: CustomDialogController = new CustomDialogController({
    builder: EnlargedCodeDialog(),
    localStorageParams: storagePaymentCode,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: true,
  });

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
            this.dialogController.open();
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