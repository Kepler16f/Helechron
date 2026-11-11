import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { webview } from '@kit.ArkWeb';

interface StreamSource {
  label: string;
  url: string;
}

function isDirectStreamUrl(url: string): boolean {
  const lower = url.toLowerCase();
  if (lower.includes('livingroom')) {
    return false;
  }
  return lower.includes('.mp4') || lower.includes('.m3u8') || lower.includes('.flv') ||
    lower.includes('.ts');
}

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'
const DOMAIN = 0x0000;
const TAG = 'HelechronIndex';
/// 悬浮底栏需要 HarmonyOS 6.0 (API 23) 及以上才支持系统沉浸材质
const MIN_API_FOR_SYSTEM_MATERIAL = 23;
const BAR_INDICES: number[] = [0, 1, 2, 3, 4];

function barSymbol(index: number): Resource {
  switch (index) {
    case 0:
      return $r('sys.symbol.clock');
    case 1:
      return $r('sys.symbol.calendar');
    case 2:
      return $r('sys.symbol.checkmark');
    case 3:
      return $r('sys.symbol.person');
    default:
      return $r('sys.symbol.gearshape');
  }
}

function barTitle(index: number): string {
  switch (index) {
    case 0:
      return '接下来';
    case 1:
      return '日程';
    case 2:
      return '任务';
    case 3:
      return '学业';
    default:
      return '设置';
  }
}

/// 读取设备 API 级别。优先使用 deviceInfo.sdkApiVersion；
/// 若不可用再尝试从 versionId（形如 "6.1.0(23)"）解析。
function resolveApiLevel(): number {
  try {
    const api = deviceInfo.sdkApiVersion;
    if (typeof api === 'number' && api > 0) {
      return api;
    }
  } catch (e) {
    // ignore
  }
  try {
    const match = deviceInfo.versionId.match(/\((\d+)\)/);
    if (match !== null) {
      return Number(match[1]);
    }
  } catch (e) {
    // ignore
  }
  return 12;
}

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";
  @StorageLink('bottomBarFloating') bottomBarFloating: boolean = false;
  @StorageLink('bottomBarImmersiveLight') bottomBarImmersiveLight: boolean = false;
  /// 沉浸光感强度档位：10=跟随系统 0=精致 1=柔和 2=流畅
  @StorageLink('bottomBarMaterialLevel') bottomBarMaterialLevel: number = 10;
  /// 弹出 Flutter 模态窗口时隐藏原生底栏，避免遮挡弹窗
  @StorageLink('bottomBarHidden') bottomBarHidden: boolean = false;
  @StorageLink('bottomBarCurrentTab') @Watch('onCurrentTabChanged') bottomBarCurrentTab: number = 0;
  @StorageLink('inAppVideoVisible') @Watch('onVideoOverlayChanged') inAppVideoVisible: boolean = false;
  @StorageLink('inAppVideoUrl') @Watch('onVideoOverlayChanged') inAppVideoUrl: string = '';
  @StorageLink('inAppVideoTitle') inAppVideoTitle: string = '智云课堂';
  @StorageLink('inAppVideoLivingroomUrl') inAppVideoLivingroomUrl: string = '';
  @StorageLink('inAppVideoToken') inAppVideoToken: string = '';
  @StorageLink('inAppVideoStreamsJson') inAppVideoStreamsJson: string = '[]';
  @State private safeBottom: number = 0;
  @State private apiLevel: number = 12;
  @State private immersiveSupported: boolean = true;
  @State private videoSpeed: PlaybackSpeed = PlaybackSpeed.Speed_Forward_1_00_X;
  @State private videoSpeedLabel: string = '1.0x';
  @State private activeVideoUrl: string = '';
  @State private activeStreamIndex: number = 0;
  @State private videoStreams: StreamSource[] = [];
  @State private useWebFallback: boolean = false;
  @State private isPlayerFullscreen: boolean = false;
  @State private isPlayerMiniWindow: boolean = false;
  @State private sensorRotation: boolean = true;
  @State private miniOffsetX: number = 0;
  @State private miniOffsetY: number = 0;
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();
  private videoController: VideoController = new VideoController();
  private webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.loadSafeArea();
    this.resolveMaterialCapability();
  }

  /// 查询设备是否支持沉浸材质；不支持时统一降级为 SMOOTH。
  private resolveMaterialCapability(): void {
    try {
      const types = hdsMaterial.getSystemMaterialTypes();
      this.immersiveSupported = types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0;
      hilog.info(DOMAIN, TAG, `materialTypes=[${types.join(',')}], immersiveSupported=${this.immersiveSupported}`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `resolveMaterialCapability failed: ${JSON.stringify(e)}`);
    }
  }

  /// 当前强度档位。应用内可覆盖系统自适应：10 交由系统策略决定。
  private currentMaterialLevel(): hdsMaterial.MaterialLevel {
    if (!this.immersiveSupported) {
      return hdsMaterial.MaterialLevel.SMOOTH;
    }
    switch (this.bottomBarMaterialLevel) {
      case 0:
        return hdsMaterial.MaterialLevel.EXQUISITE;
      case 1:
        return hdsMaterial.MaterialLevel.GENTLE;
      case 2:
        return hdsMaterial.MaterialLevel.SMOOTH;
      default:
        return hdsMaterial.MaterialLevel.ADAPTIVE;
    }
  }

  /// Flutter 侧滑动切页时同步 HdsTabs 内部选中态
  onCurrentTabChanged(): void {
    try {
      this.tabsController.changeIndex(this.bottomBarCurrentTab);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `changeIndex failed: ${JSON.stringify(e)}`);
    }
  }

  private async loadSafeArea(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.context);
      const area = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const h = px2vp(area.bottomRect.height);
      this.safeBottom = h > 0 ? h : 24;
      this.apiLevel = resolveApiLevel();
      hilog.info(DOMAIN, TAG, `safeBottom=${this.safeBottom}, apiLevel=${this.apiLevel}, versionId=${deviceInfo.versionId}`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `loadSafeArea failed: ${JSON.stringify(e)}`);
      this.safeBottom = 24;
    }
  }

  /// 是否使用系统沉浸材质（官方 HdsTabs + systemMaterialEffect，跟随系统沉浸光感强度）
  private useSystemMaterial(): boolean {
    return this.bottomBarFloating && this.bottomBarImmersiveLight
      && this.apiLevel >= MIN_API_FOR_SYSTEM_MATERIAL;
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

  onVideoOverlayChanged(): void {
    if (!this.inAppVideoVisible) {
      this.isPlayerFullscreen = false;
      this.isPlayerMiniWindow = false;
      this.miniOffsetX = 0;
      this.miniOffsetY = 0;
      this.applyPlayerWindowMode();
      return;
    }
    const parsed: StreamSource[] = [];
    try {
      const raw = JSON.parse(this.inAppVideoStreamsJson) as Record<string, Object>[];
      if (Array.isArray(raw)) {
        for (let i = 0; i < raw.length; i++) {
          const item = raw[i];
          const urlVal = item['url'];
          const labelVal = item['label'];
          if (typeof urlVal === 'string' && urlVal.length > 0 && isDirectStreamUrl(urlVal)) {
            parsed.push({
              label: typeof labelVal === 'string' && labelVal.length > 0 ? labelVal : `源${i + 1}`,
              url: urlVal
            });
          }
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `parse video streams failed: ${JSON.stringify(e)}`);
    }
    this.videoStreams = parsed;
    this.activeStreamIndex = 0;
    this.isPlayerMiniWindow = false;
    this.miniOffsetX = 0;
    this.miniOffsetY = 0;
    if (isDirectStreamUrl(this.inAppVideoUrl)) {
      this.activeVideoUrl = this.inAppVideoUrl;
      this.useWebFallback = false;
    } else if (parsed.length > 0) {
      this.activeVideoUrl = parsed[0].url;
      this.useWebFallback = false;
    } else {
      this.activeVideoUrl = this.webFallbackTarget();
      this.useWebFallback = true;
    }
    this.applyPlayerWindowMode();
  }

  private async applyPlayerWindowMode(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.context);
      if (this.inAppVideoVisible && this.isPlayerFullscreen && !this.isPlayerMiniWindow) {
        await win.setPreferredOrientation(window.Orientation.AUTO_ROTATION_LANDSCAPE);
        await win.setWindowSystemBarEnable([]);
      } else if (this.inAppVideoVisible && !this.isPlayerMiniWindow) {
        await win.setPreferredOrientation(
          this.sensorRotation
            ? window.Orientation.AUTO_ROTATION
            : window.Orientation.PORTRAIT
        );
        await win.setWindowSystemBarEnable(['status', 'navigation']);
      } else {
        await win.setPreferredOrientation(window.Orientation.UNSPECIFIED);
        await win.setWindowSystemBarEnable(['status', 'navigation']);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `applyPlayerWindowMode failed: ${JSON.stringify(e)}`);
    }
  }

  private closeVideoOverlay(): void {
    this.isPlayerFullscreen = false;
    this.isPlayerMiniWindow = false;
    this.miniOffsetX = 0;
    this.miniOffsetY = 0;
    this.inAppVideoVisible = false;
    this.applyPlayerWindowMode();
  }

  private enterLandscapeFullscreen(): void {
    this.isPlayerMiniWindow = false;
    this.isPlayerFullscreen = true;
    this.applyPlayerWindowMode();
  }

  private exitLandscapeFullscreen(): void {
    this.isPlayerFullscreen = false;
    this.applyPlayerWindowMode();
  }

  private enterMiniWindow(): void {
    this.isPlayerFullscreen = false;
    this.isPlayerMiniWindow = true;
    this.applyPlayerWindowMode();
  }

  private injectWebTokenJs(): void {
    if (this.inAppVideoToken.length === 0) {
      return;
    }
    const safeTk = this.inAppVideoToken
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'")
      .replace(/\n/g, '');
    const js = `try{localStorage.setItem('token','${safeTk}');localStorage.setItem('_token','${safeTk}');document.cookie='_token=${safeTk};path=/';document.cookie='token=${safeTk};path=/';}catch(e){}`;
    try {
      this.webController.runJavaScript(js);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `runJavaScript failed: ${JSON.stringify(e)}`);
    }
  }

  private webFallbackTarget(): string {
    if (this.inAppVideoLivingroomUrl.length > 0) {
      return this.inAppVideoLivingroomUrl;
    }
    return !isDirectStreamUrl(this.inAppVideoUrl) ? this.inAppVideoUrl : '';
  }

  private switchNextStreamOrWeb(): void {
    const nextIdx = this.activeStreamIndex + 1;
    if (nextIdx < this.videoStreams.length) {
      this.activeStreamIndex = nextIdx;
      this.activeVideoUrl = this.videoStreams[nextIdx].url;
      this.useWebFallback = false;
      return;
    }
    if (this.webFallbackTarget().length > 0) {
      this.useWebFallback = true;
    }
  }

  private cycleVideoSpeed(): void {
    if (this.videoSpeedLabel === '0.75x') {
      this.videoSpeed = PlaybackSpeed.Speed_Forward_1_00_X;
      this.videoSpeedLabel = '1.0x';
    } else if (this.videoSpeedLabel === '1.0x') {
      this.videoSpeed = PlaybackSpeed.Speed_Forward_1_25_X;
      this.videoSpeedLabel = '1.25x';
    } else if (this.videoSpeedLabel === '1.25x') {
      this.videoSpeed = PlaybackSpeed.Speed_Forward_1_75_X;
      this.videoSpeedLabel = '1.75x';
    } else if (this.videoSpeedLabel === '1.75x') {
      this.videoSpeed = PlaybackSpeed.Speed_Forward_2_00_X;
      this.videoSpeedLabel = '2.0x';
    } else {
      this.videoSpeed = PlaybackSpeed.Speed_Forward_0_75_X;
      this.videoSpeedLabel = '0.75x';
    }
  }

  /// 自绘底栏单元（低版本回退 / 非沉浸模式）
  @Builder
  BottomBarItem(index: number) {
    Column() {
      SymbolGlyph(barSymbol(index))
        .fontSize(this.bottomBarFloating ? 20 : 22)
        .fontColor([this.bottomBarCurrentTab === index
          ? $r('sys.color.ohos_id_color_emphasize')
          : $r('sys.color.ohos_id_color_text_secondary')])
      Text(barTitle(index))
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

  /// HdsTabs 页签单元：宽度交由系统均分，不再使用 layoutWeight
  @Builder
  HdsBarItem(index: number) {
    Column() {
      SymbolGlyph(barSymbol(index))
        .fontSize(22)
        .fontColor([this.bottomBarCurrentTab === index
          ? $r('sys.color.ohos_id_color_emphasize')
          : $r('sys.color.ohos_id_color_text_secondary')])
      Text(barTitle(index))
        .fontSize(10.5)
        .fontWeight(this.bottomBarCurrentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .margin({ top: 2 })
        .fontColor(this.bottomBarCurrentTab === index
          ? $r('sys.color.ohos_id_color_emphasize')
          : $r('sys.color.ohos_id_color_text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  BarItems() {
    this.BottomBarItem(0)
    this.BottomBarItem(1)
    this.BottomBarItem(2)
    this.BottomBarItem(3)
    this.BottomBarItem(4)
  }

  /// 系统沉浸材质底栏：由 HdsTabs 承载，材质强度跟随系统"沉浸光感"设置。
  /// materialLevel 使用 ADAPTIVE，由系统按设备算力与用户偏好自动分级。
  @Builder
  SystemMaterialBar() {
    HdsTabs({ controller: this.tabsController }) {
      ForEach(BAR_INDICES, (index: number) => {
        TabContent() {
        }
        .tabBar(this.HdsBarItem(index))
      }, (index: number) => index.toString())
    }
    .onTabBarClick((index: number) => {
      this.switchTab(index);
    })
    .scrollable(false)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barHeight(56)
    .barFloatingStyle({
      barBottomMargin: this.safeBottom + 8,
      adaptToHandedness: true,
      // 关闭默认的浅灰渐变蒙层，避免遮住玻璃质感（注意不能用 Color.Transparent/0，HDS 会当作未设置）
      gradientMask: { maskColor: '#00000000', maskHeight: 1 },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: this.currentMaterialLevel()
      }
    })
    .align(Alignment.Bottom)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /// 自绘沉浸光感底栏：纯背景模糊（无白色蒙版），仅 API 23 以下回退使用
  @Builder
  ImmersiveFallbackBar() {
    Row() {
      this.BarItems()
    }
    .width('92%')
    .height(56)
    .borderRadius(28)
    .clip(true)
    .margin({ bottom: this.safeBottom + 8 })
    .backgroundColor(Color.Transparent)
    .backgroundEffect({
      radius: this.apiLevel >= MIN_API_FOR_SYSTEM_MATERIAL ? 40 : 30,
      saturation: 2.0,
      brightness: 1.1
    })
    .border({ width: 0.5, color: '#26FFFFFF' })
    .shadow({ radius: 20, color: '#1A000000', offsetX: 0, offsetY: 6 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        FlutterPage({ viewId: this.viewId })
      }
      .width('100%')
      .height('100%')

      if (!this.bottomBarHidden && (!this.inAppVideoVisible || this.isPlayerMiniWindow)) {
        if (this.useSystemMaterial()) {
          this.SystemMaterialBar()
        } else if (this.bottomBarFloating) {
          if (this.bottomBarImmersiveLight) {
            this.ImmersiveFallbackBar()
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

      if (this.inAppVideoVisible && (this.inAppVideoUrl.length > 0 || this.inAppVideoLivingroomUrl.length > 0)) {
        if (this.isPlayerMiniWindow) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Column() {
              if (this.useWebFallback && this.webFallbackTarget().length > 0) {
                Web({ src: this.webFallbackTarget(), controller: this.webController })
                  .width('100%')
                  .height('100%')
                  .javaScriptAccess(true)
                  .domStorageAccess(true)
                  .mediaPlayGestureAccess(false)
                  .mixedMode(MixedMode.All)
                  .onPageBegin(() => {
                    this.injectWebTokenJs();
                  })
                  .onPageEnd(() => {
                    this.injectWebTokenJs();
                  })
              } else {
                Video({
                  src: this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl,
                  currentProgressRate: this.videoSpeed,
                  controller: this.videoController
                })
                  .width('100%')
                  .height('100%')
                  .autoPlay(true)
                  .controls(true)
                  .objectFit(ImageFit.Contain)
                  .backgroundColor(Color.Black)
                  .onError(() => {
                    this.switchNextStreamOrWeb();
                  })
              }
            }
            .width('100%')
            .height('100%')

            Row({ space: 6 }) {
              Button('全屏')
                .height(24)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .backgroundColor('#99000000')
                .fontColor(Color.White)
                .onClick(() => {
                  this.enterLandscapeFullscreen();
                })
              Button('✕')
                .height(24)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .backgroundColor('#99000000')
                .fontColor(Color.White)
                .onClick(() => {
                  this.closeVideoOverlay();
                })
            }
            .margin({ top: 6, right: 6 })
          }
          .width(264)
          .height(148)
          .borderRadius(12)
          .clip(true)
          .backgroundColor(Color.Black)
          .border({ width: 1, color: '#44FFFFFF' })
          .shadow({ radius: 18, color: '#66000000', offsetX: 0, offsetY: 6 })
          .margin({ right: 14, bottom: this.safeBottom + 72 })
          .translate({ x: this.miniOffsetX, y: this.miniOffsetY })
          .gesture(
            PanGesture()
              .onActionStart(() => {
                this.dragStartX = this.miniOffsetX;
                this.dragStartY = this.miniOffsetY;
              })
              .onActionUpdate((event: GestureEvent) => {
                this.miniOffsetX = this.dragStartX + event.offsetX;
                this.miniOffsetY = this.dragStartY + event.offsetY;
              })
          )
        } else {
          Stack({ alignContent: Alignment.TopEnd }) {
            Column() {
              if (!this.isPlayerFullscreen) {
                Row() {
                  Button('关闭')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#33FFFFFF')
                    .fontColor(Color.White)
                    .onClick(() => {
                      this.closeVideoOverlay();
                    })

                  Text(this.inAppVideoTitle)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                    .margin({ left: 8, right: 8 })

                  if (!this.useWebFallback && this.videoStreams.length > 1) {
                    Button('换源')
                      .height(30)
                      .fontSize(12)
                      .backgroundColor('#33FFFFFF')
                      .fontColor(Color.White)
                      .margin({ right: 6 })
                      .onClick(() => {
                        const nextIdx = (this.activeStreamIndex + 1) % this.videoStreams.length;
                        this.activeStreamIndex = nextIdx;
                        this.activeVideoUrl = this.videoStreams[nextIdx].url;
                      })
                  }

                  if (!this.useWebFallback) {
                    Button(this.videoSpeedLabel)
                      .height(30)
                      .fontSize(12)
                      .backgroundColor('#33FFFFFF')
                      .fontColor(Color.White)
                      .margin({ right: 6 })
                      .onClick(() => {
                        this.cycleVideoSpeed();
                      })
                  }

                  if (!this.useWebFallback && this.webFallbackTarget().length > 0) {
                    Button('网页')
                      .height(30)
                      .fontSize(12)
                      .backgroundColor('#330A84FF')
                      .fontColor(Color.White)
                      .margin({ right: 6 })
                      .onClick(() => {
                        this.useWebFallback = true;
                      })
                  }

                  Button(this.sensorRotation ? '旋屏' : '锁定')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#33FFFFFF')
                    .fontColor(Color.White)
                    .margin({ right: 6 })
                    .onClick(() => {
                      this.sensorRotation = !this.sensorRotation;
                      this.applyPlayerWindowMode();
                    })

                  Button('小窗')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#3330D158')
                    .fontColor(Color.White)
                    .margin({ right: 6 })
                    .onClick(() => {
                      this.enterMiniWindow();
                    })

                  Button('全屏')
                    .height(30)
                    .fontSize(12)
                    .backgroundColor('#44FFFFFF')
                    .fontColor(Color.White)
                    .onClick(() => {
                      this.enterLandscapeFullscreen();
                    })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 44, bottom: 10 })
                .backgroundColor('#E6000000')
              }

              if (this.useWebFallback && this.webFallbackTarget().length > 0) {
                Web({ src: this.webFallbackTarget(), controller: this.webController })
                  .width('100%')
                  .layoutWeight(1)
                  .javaScriptAccess(true)
                  .domStorageAccess(true)
                  .mediaPlayGestureAccess(false)
                  .mixedMode(MixedMode.All)
                  .onControllerAttached(() => {
                    if (this.inAppVideoToken.length > 0) {
                      try {
                        const hosts = [
                          'https://classroom.zju.edu.cn',
                          'https://yjapi.cmc.zju.edu.cn',
                          'https://tgmedia.cmc.zju.edu.cn'
                        ];
                        for (let i = 0; i < hosts.length; i++) {
                          webview.WebCookieManager.configCookieSync(hosts[i], `_token=${this.inAppVideoToken}; Path=/`);
                          webview.WebCookieManager.configCookieSync(hosts[i], `token=${this.inAppVideoToken}; Path=/`);
                          webview.WebCookieManager.configCookieSync(hosts[i], `_token=${this.inAppVideoToken}; Domain=.zju.edu.cn; Path=/`);
                          webview.WebCookieManager.configCookieSync(hosts[i], `token=${this.inAppVideoToken}; Domain=.zju.edu.cn; Path=/`);
                        }
                      } catch (err) {
                        hilog.warn(DOMAIN, TAG, `configCookieSync failed: ${JSON.stringify(err)}`);
                      }
                    }
                  })
                  .onPageBegin(() => {
                    this.injectWebTokenJs();
                  })
                  .onPageEnd(() => {
                    this.injectWebTokenJs();
                  })
              } else {
                Video({
                  src: this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl,
                  currentProgressRate: this.videoSpeed,
                  controller: this.videoController
                })
                  .width('100%')
                  .layoutWeight(1)
                  .autoPlay(true)
                  .controls(true)
                  .objectFit(ImageFit.Contain)
                  .backgroundColor(Color.Black)
                  .onError(() => {
                    this.switchNextStreamOrWeb();
                  })
              }
            }
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Black)

            if (this.isPlayerFullscreen) {
              Row({ space: 8 }) {
                Button('小窗')
                  .height(30)
                  .fontSize(12)
                  .backgroundColor('#80000000')
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.enterMiniWindow();
                  })
                Button('退出全屏')
                  .height(30)
                  .fontSize(12)
                  .backgroundColor('#80000000')
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.exitLandscapeFullscreen();
                  })
                Button('关闭')
                  .height(30)
                  .fontSize(12)
                  .backgroundColor('#80000000')
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.closeVideoOverlay();
                  })
              }
              .margin({ top: 14, right: 16 })
            }
          }
          .width('100%')
          .height('100%')
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    if (this.inAppVideoVisible) {
      if (this.isPlayerFullscreen) {
        this.exitLandscapeFullscreen();
      } else {
        this.closeVideoOverlay();
      }
      return true;
    }
    this.context.eventHub.emit(EVENT_BACK_PRESS);
    return true;
  }
}
