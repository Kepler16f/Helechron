import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, BlurStyle } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'
const DOMAIN = 0x0000;
const TAG = 'HelechronIndex';

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";
  @StorageLink('bottomBarFloating') bottomBarFloating: boolean = false;
  @StorageLink('bottomBarImmersiveLight') bottomBarImmersiveLight: boolean = false;
  @StorageLink('bottomBarCurrentTab') bottomBarCurrentTab: number = 0;
  @State private safeBottom: number = 0;
  @State private apiLevel: number = 12;

  aboutToAppear(): void {
    this.loadSafeArea();
  }

  private async loadSafeArea(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.context);
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const h = px2vp(area.bottomRect.height);
      this.safeBottom = h > 0 ? h : 24;
      this.apiLevel = deviceInfo.versionAPI;
      hilog.info(DOMAIN, TAG, `safeBottom=${this.safeBottom}, apiLevel=${this.apiLevel}`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `loadSafeArea failed: ${JSON.stringify(e)}`);
      this.safeBottom = 24;
    }
  }

  private switchTab(index: number): void {
    if (index === this.bottomBarCurrentTab) {
      return;
    }
    this.bottomBarCurrentTab = index;
    try {
      this.context.eventHub.emit('bottomBarTabChanged', index);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `emit bottomBarTabChanged failed: ${JSON.stringify(e)}`);
    }
  }

  @Builder
  BottomBarItem(symbol: Resource, title: string, index: number) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(this.bottomBarFloating ? 20 : 22)
        .fontColor([this.bottomBarCurrentTab === index
          ? $r('sys.color.ohos_id_color_emphasize')
          : $r('sys.color.ohos_id_color_text_secondary')])
      Text(title)
        .fontSize(this.bottomBarFloating ? 9 : 10)
        .margin({ top: this.bottomBarFloating ? 1 : 2 })
        .fontColor(this.bottomBarCurrentTab === index
          ? $r('sys.color.ohos_id_color_emphasize')
          : $r('sys.color.ohos_id_color_text_secondary'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.switchTab(index);
    })
  }

  @Builder
  BarItems() {
    this.BottomBarItem($r('sys.symbol.clock'), '接下来', 0)
    this.BottomBarItem($r('sys.symbol.calendar'), '日程', 1)
    this.BottomBarItem($r('sys.symbol.checkmark'), '任务', 2)
    this.BottomBarItem($r('sys.symbol.person'), '学业', 3)
    this.BottomBarItem($r('sys.symbol.gearshape'), '设置', 4)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        FlutterPage({ viewId: this.viewId })
      }
      .width('100%')
      .height('100%')

      if (this.bottomBarFloating) {
        if (this.bottomBarImmersiveLight) {
          if (this.apiLevel >= 23) {
            // API 23+ (HarmonyOS 6.1+): 更强的系统级模糊 + 高饱和
            Row() {
              this.BarItems()
            }
            .width('92%')
            .height(56)
            .borderRadius(28)
            .clip(true)
            .margin({ bottom: this.safeBottom + 8 })
            .backgroundBlurStyle(BlurStyle.Regular)
            .backgroundEffect({
              radius: 50,
              saturation: 2.2,
              brightness: 1.25
            })
            .linearGradient({
              angle: 180,
              colors: [
                ['#55FFFFFF', 0.0],
                ['#22FFFFFF', 0.30],
                ['#00FFFFFF', 0.60]
              ]
            })
            .border({ width: 0.7, color: '#66FFFFFF' })
            .shadow({ radius: 30, color: '#33000000', offsetX: 0, offsetY: 10 })
          } else {
            // API 12-22: 基础液态玻璃效果
            Row() {
              this.BarItems()
            }
            .width('92%')
            .height(56)
            .borderRadius(28)
            .clip(true)
            .margin({ bottom: this.safeBottom + 8 })
            .backgroundBlurStyle(BlurStyle.Regular)
            .backgroundEffect({
              radius: 40,
              saturation: 1.8,
              brightness: 1.15
            })
            .linearGradient({
              angle: 180,
              colors: [
                ['#4DFFFFFF', 0.0],
                ['#1AFFFFFF', 0.35],
                ['#00FFFFFF', 0.65]
              ]
            })
            .border({ width: 0.5, color: '#59FFFFFF' })
            .shadow({ radius: 24, color: '#2E000000', offsetX: 0, offsetY: 8 })
          }
        } else {
          Row() {
            this.BarItems()
          }
          .width('92%')
          .height(56)
          .borderRadius(28)
          .clip(true)
          .margin({ bottom: this.safeBottom + 8 })
          .backgroundColor($r('sys.color.ohos_id_color_bottom_tab_bg'))
          .shadow({ radius: 16, color: '#1F000000', offsetX: 0, offsetY: 6 })
        }
      } else {
        Row() {
          this.BarItems()
        }
        .width('100%')
        .height(56 + this.safeBottom)
        .padding({ bottom: this.safeBottom })
        .backgroundColor($r('sys.color.ohos_id_color_bottom_tab_bg'))
      }
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
