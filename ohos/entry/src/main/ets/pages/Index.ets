import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import { hilog } from '@kit.PerformanceAnalysisKit';

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
        .fontSize(22)
        .fontColor([this.bottomBarCurrentTab === index
          ? $r('sys.color.ohos_id_color_emphasize')
          : $r('sys.color.ohos_id_color_text_secondary')])
      Text(title)
        .fontSize(10)
        .margin({ top: 2 })
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

  build() {
    Stack() {
      Column() {
        FlutterPage({ viewId: this.viewId })
      }
      .width('100%')
      .height('100%')

      if (this.bottomBarFloating) {
        Column() {
          Blank()
          Row() {
            this.BottomBarItem($r('sys.symbol.clock'), '接下来', 0)
            this.BottomBarItem($r('sys.symbol.calendar'), '日程', 1)
            this.BottomBarItem($r('sys.symbol.checkmark'), '任务', 2)
            this.BottomBarItem($r('sys.symbol.person'), '学业', 3)
            this.BottomBarItem($r('sys.symbol.gearshape'), '设置', 4)
          }
          .width('92%')
          .height(56)
          .borderRadius(28)
          .clip(true)
          .margin({ bottom: 20 })
          .backgroundEffect({ radius: 30 })
          .backgroundColor(this.bottomBarImmersiveLight
            ? Color.Transparent
            : $r('sys.color.ohos_id_color_bottom_tab_bg'))
        }
        .width('100%')
        .height('100%')
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
