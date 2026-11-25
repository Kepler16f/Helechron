let storagePaymentCode = new LocalStorage();

@Entry(storagePaymentCode)
@Component
struct PaymentCodeWidget {
  @LocalStorageProp('paymentCode') paymentCode: string = '';
  @LocalStorageProp('displayName') displayName: string = '付款码';
  @LocalStorageProp('hasCode') hasCode: string = '0';
  @LocalStorageProp('accentColor') accentColor: string = '#007AFF';

  build() {
    Column() {
      // 顶部标题与双操作圆钮（严格单行）
      Row({ space: 5 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.accentColor)
        Text(this.displayName)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.widget_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.hasCode === '1' && this.paymentCode.length > 0) {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_widget_enlarge'))
              .width(13)
              .height(13)
              .fillColor(this.accentColor)
          }
          .width(26)
          .height(26)
          .backgroundColor($r('app.color.widget_tonal_surface'))
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              bundleName: 'top.celechron.helechron',
              abilityName: 'EnlargedQRAbility',
              params: {
                target: 'enlarged_qr',
                paymentCode: this.paymentCode
              }
            });
          })

          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_widget_refresh'))
              .width(13)
              .height(13)
              .fillColor($r('app.color.widget_button_text'))
          }
          .width(26)
          .height(26)
          .backgroundColor(this.accentColor)
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
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 6 })

      if (this.hasCode === '1' && this.paymentCode.length > 0) {
        Column() {
          Column() {
            QRCode(this.paymentCode)
              .width('100%')
              .height('100%')
              .color('#000000')
              .backgroundColor('#FFFFFF')
          }
          .layoutWeight(1)
          .aspectRatio(1)
          .alignSelf(ItemAlign.Center)
          .constraintSize({ maxWidth: '100%' })
          .padding(5)
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
          .border({ width: 0.5, color: $r('app.color.widget_qr_border') })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(5)
        .borderRadius(13)
        .backgroundColor($r('app.color.widget_tonal_surface'))
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            bundleName: 'top.celechron.helechron',
            abilityName: 'EntryAbility',
            params: {
              target: 'ecardpaypage'
            }
          });
        })
      } else {
        Column({ space: 4 }) {
          Text('点击打开付款码')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.accentColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text('打开应用后自动同步')
            .fontSize(10.5)
            .fontColor($r('app.color.widget_text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .layoutWeight(1)
        .padding(8)
        .borderRadius(13)
        .backgroundColor($r('app.color.widget_tonal_surface'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            bundleName: 'top.celechron.helechron',
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
    .borderRadius(20)
  }
}
