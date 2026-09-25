import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'EnlargedQRAbility';

export default class EnlargedQRAbility extends UIAbility {
  private windowStage: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EnlargedQRAbility onCreate');
    this.extractPaymentCode(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EnlargedQRAbility onNewWant');
    this.extractPaymentCode(want);
  }

  private extractPaymentCode(want: Want): void {
    if (want.parameters) {
      const code: string = (want.parameters['paymentCode'] as string) || '';
      if (code.length > 0) {
        AppStorage.setOrCreate('enlargedQrPaymentCode', code);
      }
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStage = windowStage;
    try {
      windowStage.getMainWindow().then((mainWindow: window.Window) => {
        try {
          mainWindow.setWindowBackgroundColor('#00000000');
          mainWindow.setWindowLayoutFullScreen(true);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, `setWindowBackgroundColor failed: ${JSON.stringify(e)}`);
        }
      }).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `getMainWindow failed: ${JSON.stringify(err)}`);
      });

      windowStage.loadContent('pages/EnlargedQRPage', (err: BusinessError) => {
        if (err) {
          hilog.error(DOMAIN, TAG, `loadContent EnlargedQRPage failed: ${JSON.stringify(err)}`);
        } else {
          hilog.info(DOMAIN, TAG, 'loadContent EnlargedQRPage success');
        }
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, `onWindowStageCreate exception: ${JSON.stringify(e)}`);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EnlargedQRAbility onDestroy');
    AppStorage.setOrCreate('enlargedQrPaymentCode', '');
  }
}
