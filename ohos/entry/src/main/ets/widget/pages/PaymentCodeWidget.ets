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
          .fontColor('#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)

      // 主体内容
      if (this.hasCode === '1' && this.paymentCode.length > 0) {
        Column() {
          QRCode(this.paymentCode)
            .width('68%')
            .aspectRatio(1)
            .color('#000000')
            .backgroundColor('#FFFFFF')

          Text(this.paymentCode)
            .fontSize(10)
            .fontColor('#888888')
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 4 }) {
          Text('点击打开付款码')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#1E88E5')

          Text('打开应用后自动同步')
            .fontSize(10)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
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
