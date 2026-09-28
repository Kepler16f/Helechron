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
    if (this.windowStage) {
      try {
        this.windowStage.getMainWindow().then((mainWindow: window.Window) => {
          try {
            mainWindow.setWindowBackgroundColor('#00000000');
            mainWindow.setWindowLayoutFullScreen(true);
            mainWindow.showWindow();
          } catch (e) {}
        }).catch(() => {});

        this.windowStage.loadContent('pages/EnlargedQRPage', (err: BusinessError) => {
          if (err) {
            hilog.error(DOMAIN, TAG, `onNewWant loadContent failed: ${JSON.stringify(err)}`);
          } else {
            hilog.info(DOMAIN, TAG, 'onNewWant reloadContent success');
          }
        });
      } catch (e) {
        hilog.error(DOMAIN, TAG, `onNewWant exception: ${JSON.stringify(e)}`);
      }
    }
  }

  private extractPaymentCode(want: Want): void {
    if (want.parameters) {
      let code: string = (want.parameters['paymentCode'] as string) || '';
      if (!code && want.parameters['params']) {
        const inner = want.parameters['params'] as Record<string, Object> | string;
        if (typeof inner === 'object' && inner !== null) {
          code = (inner['paymentCode'] as string) || '';
        } else if (typeof inner === 'string') {
          try {
            const parsed = JSON.parse(inner) as Record<string, Object>;
            code = (parsed['paymentCode'] as string) || '';
          } catch (e) {}
        }
      }
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
