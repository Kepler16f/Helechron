import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

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

  aboutToAppear(): void {
    this.loadSafeArea();
  }

  private async loadSafeArea(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.context);
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const h = px2vp(area.bottomRect.height);
      this.safeBottom = h > 0 ? h : 24;
      hilog.info(DOMAIN, TAG, `safeBottom=${this.safeBottom}`);
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
          // 沉浸光感液态玻璃：毛玻璃 + 高饱和/提亮 + 自适应背景色 + 高光渐变 + 边缘描边 + 底部投影
          Row() {
            this.BarItems()
          }
          .width('92%')
          .height(56)
          .borderRadius(28)
          .clip(true)
          .margin({ bottom: this.safeBottom + 8 })
          .backgroundEffect({
            radius: 40,
            saturation: 2.0,
            brightness: 1.18,
            color: '#18FFFFFF',
            adaptiveColor: AdaptiveColor.AVERAGE
          })
          .linearGradient({
            angle: 180,
            colors: [
              ['#50FFFFFF', 0.0],
              ['#1AFFFFFF', 0.40],
              ['#00FFFFFF', 0.72]
            ]
          })
          .border({ width: 1, color: '#4DFFFFFF' })
          .shadow({ radius: 28, color: '#38000000', offsetX: 0, offsetY: 10 })
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
