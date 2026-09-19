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

  private tabsController: TabsController = new TabsController();

  @Builder
  TabItem(title: string, index: number) {
    Column() {
      Text(title)
        .fontColor(this.bottomBarCurrentTab === index ? $r('sys.color.ohos_id_color_emphasize') : $r('sys.color.ohos_id_color_text_secondary'))
        .fontSize(12)
        .fontWeight(this.bottomBarCurrentTab === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
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
            Tabs({ index: this.bottomBarCurrentTab, controller: this.tabsController }) {
              TabContent() {
                this.TabItem('接下来', 0)
              }.tabBar(new BottomTabBarStyle($r('sys.symbol.clock'), '接下来'))

              TabContent() {
                this.TabItem('日程', 1)
              }.tabBar(new BottomTabBarStyle($r('sys.symbol.calendar'), '日程'))

              TabContent() {
                this.TabItem('任务', 2)
              }.tabBar(new BottomTabBarStyle($r('sys.symbol.checkmark'), '任务'))

              TabContent() {
                this.TabItem('学业', 3)
              }.tabBar(new BottomTabBarStyle($r('sys.symbol.person'), '学业'))

              TabContent() {
                this.TabItem('设置', 4)
              }.tabBar(new BottomTabBarStyle($r('sys.symbol.gearshape'), '设置'))
            }
            .barPosition(BarPosition.End)
            .barMode(BarMode.Fixed)
            .barOverlap(true)
            .vertical(false)
            .onChange((index: number) => {
              if (index !== this.bottomBarCurrentTab) {
                this.bottomBarCurrentTab = index;
                try {
                  this.context.eventHub.emit('bottomBarTabChanged', index);
                } catch (e) {
                  hilog.warn(DOMAIN, TAG, `emit bottomBarTabChanged failed: ${JSON.stringify(e)}`);
                }
              }
            })
            .width('100%')
            .height(56)
          }
          .width('92%')
          .height(56)
          .borderRadius(28)
          .clip(true)
          .margin({ bottom: 12 })
          .backgroundEffect({ radius: 30 })
          .backgroundColor(this.bottomBarImmersiveLight ? Color.Transparent : $r('sys.color.ohos_id_color_bottom_tab_bg'))
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
