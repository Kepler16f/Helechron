import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PiPWindow, window } from '@kit.ArkUI';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { sensor } from '@kit.SensorServiceKit';
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { webview } from '@kit.ArkWeb';

interface StreamSource {
  label: string;
  url: string;
}

function formatVideoTime(rawSec: number): string {
  const total = Math.max(0, Math.floor(rawSec));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const mm = m < 10 ? `0${m}` : `${m}`;
  const ss = s < 10 ? `0${s}` : `${s}`;
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
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
  @State private safeBottom: number = 24;
  @State private safeTop: number = 36;
  @State private safeLeft: number = 0;
  @State private safeRight: number = 0;
  @State private apiLevel: number = 12;
  @State private immersiveSupported: boolean = true;
  @State private videoSpeedLabel: string = '1.0x';
  @State private activeVideoUrl: string = '';
  @State private activeStreamIndex: number = 0;
  @State private videoStreams: StreamSource[] = [];
  @State private useWebFallback: boolean = false;
  @State private isPlayerFullscreen: boolean = false;
  @State private isPlayerMiniWindow: boolean = false;
  @State private isSystemPipActive: boolean = false;
  @State private isFloatingWindow: boolean = false;
  @State private isSplitWindow: boolean = false;
  @State private isFreeWindowMode: boolean = false;
  @State private winWidthVp: number = 0;
  @State private winHeightVp: number = 0;
  @State private sensorRotation: boolean = true;
  @State private controlsVisible: boolean = true;
  @State private showMoreSheet: boolean = false;
  @State private isVideoPlaying: boolean = true;
  @State private videoLoading: boolean = true;
  @State private videoCurrentTime: number = 0;
  @State private videoDuration: number = 0;
  @State private videoAspectRatio: number = 16 / 9;
  @State private playerContainerAspect: number = 0.56;
  @State private playerContainerW: number = 0;
  @State private playerContainerH: number = 0;
  @State private isSeeking: boolean = false;
  @State private hudText: string = '';
  @State private miniOffsetX: number = 0;
  @State private miniOffsetY: number = 0;
  private avSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  private videoContentWidth: number = 1920;
  private videoContentHeight: number = 1080;
  private xComponentSurfaceId: string = '';
  private avPlayer: media.AVPlayer | undefined = undefined;
  private pipController: PiPWindow.PiPController | undefined = undefined;
  private mainWindow: window.Window | undefined = undefined;
  private pipRestoring: boolean = false;
  private landscapeMultiWindowEnabled: boolean = false;
  private lastManualPlayToggleMs: number = 0;
  private manualTargetPlaying: boolean = true;
  private manualFullscreenLock: boolean = false;
  private sensorSubscribed: boolean = false;
  private currentOri: window.Orientation = window.Orientation.UNSPECIFIED;
  private lastSensorRotateMs: number = 0;
  private hideOverlayTimer: number = -1;
  private hudTimer: number = -1;
  private prepareWatchdogTimer: number = -1;
  private dragStartX: number = 0;
  private dragStartY: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();
  private xComponentController: XComponentController = new XComponentController();
  private webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    this.loadSafeArea();
    this.resolveMaterialCapability();
  }

  aboutToDisappear(): void {
    this.stopGravitySensor();
    this.clearOverlayTimers();
    this.setLandscapeMultiWindowEnabled(false);
    this.unregisterWindowListeners();
    this.releaseSystemPip();
    this.releaseAvPlayer();
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

  private unregisterWindowListeners(): void {
    const win = this.mainWindow;
    if (win === undefined) {
      return;
    }
    try {
      win.off('avoidAreaChange');
    } catch (_) {
    }
    try {
      win.off('windowStatusChange');
    } catch (_) {
    }
    try {
      win.off('windowSizeChange');
    } catch (_) {
    }
    this.mainWindow = undefined;
  }

  private isSystemMultiWindow(): boolean {
    return this.isFloatingWindow || this.isSplitWindow;
  }

  private isCompactSmallWindow(): boolean {
    if (this.isSystemMultiWindow()) {
      return true;
    }
    return this.winWidthVp > 0 && this.winWidthVp < 420 && this.winHeightVp > 0 && this.winHeightVp < 560;
  }

  private refreshWindowMetrics(win: window.Window): void {
    try {
      const props = win.getWindowProperties();
      const rect = props.windowRect;
      if (rect.width > 0 && rect.height > 0) {
        this.winWidthVp = px2vp(rect.width);
        this.winHeightVp = px2vp(rect.height);
      }
    } catch (_) {
    }
    try {
      this.isFreeWindowMode = win.isInFreeWindowMode();
    } catch (_) {
    }
  }

  private async setLandscapeMultiWindowEnabled(enable: boolean): Promise<void> {
    if (this.landscapeMultiWindowEnabled === enable) {
      return;
    }
    this.landscapeMultiWindowEnabled = enable;
    try {
      const win = this.mainWindow ?? await window.getLastWindow(this.context);
      if (enable) {
        await win.enableLandscapeMultiWindow();
      } else {
        await win.disableLandscapeMultiWindow();
      }
    } catch (e) {
      const be = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `setLandscapeMultiWindowEnabled(${enable}) failed: ${be.code} ${be.message}`);
    }
  }

  private syncLandscapeMultiWindow(): void {
    // 参照 PiliPlus WindowState：非自由窗口模式下，播放横屏视频/全屏且未进入系统画中画时启用横向小窗，
    // 挂起为系统悬浮小窗后窗口自动横置铺满；进入系统画中画前须关闭以避免小窗进 PiP 黑屏。
    const shouldEnable = this.inAppVideoVisible
      && !this.useWebFallback
      && !this.isSystemPipActive
      && !this.isPlayerMiniWindow
      && !this.isFreeWindowMode
      && (this.isPlayerFullscreen || (this.isFloatingWindow && this.videoAspectRatio >= 1.05) || this.videoAspectRatio >= 1.15);
    this.setLandscapeMultiWindowEnabled(shouldEnable);
  }

  private refreshAvoidAreas(win: window.Window): void {
    try {
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const sysArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const b = Math.max(px2vp(navArea.bottomRect.height), px2vp(sysArea.bottomRect.height), px2vp(cutoutArea.bottomRect.height));
      const t = Math.max(px2vp(sysArea.topRect.height), px2vp(cutoutArea.topRect.height));
      const l = Math.max(px2vp(sysArea.leftRect.width), px2vp(cutoutArea.leftRect.width));
      const r = Math.max(px2vp(sysArea.rightRect.width), px2vp(cutoutArea.rightRect.width));
      const inMulti = this.isSystemMultiWindow();
      this.safeBottom = b > 0 ? b : (inMulti ? 0 : 24);
      this.safeTop = t > 0 ? t : (inMulti ? 0 : 16);
      this.safeLeft = l;
      this.safeRight = r;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `refreshAvoidAreas failed: ${JSON.stringify(e)}`);
    }
  }

  private async loadSafeArea(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.context);
      this.mainWindow = win;
      this.refreshWindowMetrics(win);
      this.refreshAvoidAreas(win);
      this.apiLevel = resolveApiLevel();
      win.on('avoidAreaChange', () => {
        this.refreshAvoidAreas(win);
      });
      try {
        win.on('windowSizeChange', (size: window.Size) => {
          if (size.width > 0 && size.height > 0) {
            this.winWidthVp = px2vp(size.width);
            this.winHeightVp = px2vp(size.height);
          }
          this.refreshWindowMetrics(win);
          this.refreshAvoidAreas(win);
          this.syncLandscapeMultiWindow();
        });
      } catch (wsErr) {
        hilog.warn(DOMAIN, TAG, `windowSizeChange subscribe failed: ${JSON.stringify(wsErr)}`);
      }
      try {
        win.on('windowStatusChange', (status: window.WindowStatusType) => {
          this.isFloatingWindow = status === window.WindowStatusType.FLOATING;
          this.isSplitWindow = status === window.WindowStatusType.SPLIT_SCREEN;
          this.refreshWindowMetrics(win);
          this.refreshAvoidAreas(win);
          this.syncLandscapeMultiWindow();
        });
      } catch (stErr) {
        hilog.warn(DOMAIN, TAG, `windowStatusChange subscribe failed: ${JSON.stringify(stErr)}`);
      }
      hilog.info(DOMAIN, TAG, `safeTop=${this.safeTop}, safeBottom=${this.safeBottom}, apiLevel=${this.apiLevel}, versionId=${deviceInfo.versionId}`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `loadSafeArea failed: ${JSON.stringify(e)}`);
      this.safeBottom = 24;
      this.safeTop = 36;
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
      this.manualFullscreenLock = false;
      this.isPlayerFullscreen = false;
      this.isPlayerMiniWindow = false;
      this.isSystemPipActive = false;
      this.pipRestoring = false;
      this.showMoreSheet = false;
      this.controlsVisible = true;
      this.miniOffsetX = 0;
      this.miniOffsetY = 0;
      this.xComponentSurfaceId = '';
      this.stopGravitySensor();
      this.clearOverlayTimers();
      this.setLandscapeMultiWindowEnabled(false);
      this.releaseSystemPip();
      this.releaseAvPlayer();
      this.applyPlayerWindowMode(window.Orientation.UNSPECIFIED, false);
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
              label: typeof labelVal === 'string' && labelVal.length > 0 ? labelVal : `线路 ${i + 1}`,
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
    this.manualFullscreenLock = false;
    this.isPlayerFullscreen = false;
    this.isPlayerMiniWindow = false;
    this.isSystemPipActive = false;
    this.showMoreSheet = false;
    this.controlsVisible = true;
    this.videoLoading = true;
    this.videoCurrentTime = 0;
    this.videoDuration = 0;
    this.isVideoPlaying = true;
    this.manualTargetPlaying = true;
    this.pipRestoring = false;
    this.miniOffsetX = 0;
    this.miniOffsetY = 0;
    this.preConfigureWebCookies();
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
    this.applyPlayerWindowMode(this.isSystemMultiWindow() ? window.Orientation.UNSPECIFIED : window.Orientation.PORTRAIT, false);
    this.syncLandscapeMultiWindow();
    if (this.sensorRotation) {
      this.startGravitySensor();
    }
    if (!this.useWebFallback && this.xComponentSurfaceId.length > 0) {
      this.startAvPlayerPlayback(this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl);
    }
    this.scheduleHideOverlay();
  }

  private clearPrepareWatchdog(): void {
    if (this.prepareWatchdogTimer !== -1) {
      clearTimeout(this.prepareWatchdogTimer);
      this.prepareWatchdogTimer = -1;
    }
  }

  private clearOverlayTimers(): void {
    if (this.hideOverlayTimer !== -1) {
      clearTimeout(this.hideOverlayTimer);
      this.hideOverlayTimer = -1;
    }
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    this.clearPrepareWatchdog();
  }

  private showHudMessage(msg: string): void {
    this.hudText = msg;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout(() => {
      this.hudText = '';
      this.hudTimer = -1;
    }, 1600);
  }

  private scheduleHideOverlay(): void {
    if (this.hideOverlayTimer !== -1) {
      clearTimeout(this.hideOverlayTimer);
      this.hideOverlayTimer = -1;
    }
    if (!this.useWebFallback && this.isVideoPlaying && !this.showMoreSheet && !this.isPlayerMiniWindow) {
      this.hideOverlayTimer = setTimeout(() => {
        this.controlsVisible = false;
        this.hideOverlayTimer = -1;
      }, 3600);
    }
  }

  private startGravitySensor(): void {
    if (this.sensorSubscribed) {
      return;
    }
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (data: sensor.AccelerometerResponse) => {
        this.handleAccelerometerData(data.x, data.y, data.z);
      }, { interval: 200000000 });
      this.sensorSubscribed = true;
      hilog.info(DOMAIN, TAG, 'Gravity sensor subscribed for video orientation');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `startGravitySensor failed: ${JSON.stringify(e)}`);
    }
  }

  private stopGravitySensor(): void {
    if (!this.sensorSubscribed) {
      return;
    }
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `stopGravitySensor failed: ${JSON.stringify(e)}`);
    }
    this.sensorSubscribed = false;
  }

  private handleAccelerometerData(x: number, y: number, z: number): void {
    if (!this.inAppVideoVisible || !this.sensorRotation || this.isPlayerMiniWindow || this.isSystemPipActive || this.isSystemMultiWindow()) {
      return;
    }
    // 手机几乎平放桌面时忽略重力微扰
    if (Math.abs(z) > 7.8) {
      return;
    }
    const now = Date.now();
    if (now - this.lastSensorRotateMs < 650) {
      return;
    }
    let nextOri: window.Orientation | null = null;
    if (x > 6.6 && Math.abs(y) < 4.8) {
      nextOri = window.Orientation.LANDSCAPE;
    } else if (x < -6.6 && Math.abs(y) < 4.8) {
      nextOri = window.Orientation.LANDSCAPE_INVERTED;
    } else if (!this.manualFullscreenLock && y > 7.2 && Math.abs(x) < 3.6) {
      nextOri = window.Orientation.PORTRAIT;
    }
    if (nextOri === null || nextOri === this.currentOri) {
      return;
    }
    this.lastSensorRotateMs = now;
    const landscape = nextOri === window.Orientation.LANDSCAPE ||
      nextOri === window.Orientation.LANDSCAPE_INVERTED;
    this.isPlayerFullscreen = landscape;
    this.applyPlayerWindowMode(nextOri, landscape);
  }

  private async applyPlayerWindowMode(
    targetOri: window.Orientation,
    hideBars: boolean
  ): Promise<void> {
    this.currentOri = targetOri;
    try {
      const win = this.mainWindow ?? await window.getLastWindow(this.context);
      if (!this.isSystemMultiWindow() || targetOri === window.Orientation.UNSPECIFIED) {
        await win.setPreferredOrientation(targetOri);
      }
      if (this.inAppVideoVisible && hideBars && !this.isPlayerMiniWindow && !this.isSystemPipActive && !this.isSystemMultiWindow()) {
        await win.setWindowSystemBarEnable([]);
      } else {
        await win.setWindowSystemBarEnable(['status', 'navigation']);
      }
      this.refreshAvoidAreas(win);
      this.syncLandscapeMultiWindow();
    } catch (e) {
      const be = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `applyPlayerWindowMode failed: ${be.code} ${be.message}`);
    }
  }

  private async releaseAvPlayer(): Promise<void> {
    this.clearPrepareWatchdog();
    const p = this.avPlayer;
    this.avPlayer = undefined;
    if (p !== undefined) {
      try {
        await p.reset();
        await p.release();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `releaseAvPlayer failed: ${JSON.stringify(e)}`);
      }
    }
  }

  private syncPipPlaybackState(): void {
    const pip = this.pipController;
    if (pip === undefined) {
      return;
    }
    try {
      const status: PiPWindow.PiPControlStatus = this.isVideoPlaying
        ? PiPWindow.PiPControlStatus.PLAY
        : PiPWindow.PiPControlStatus.PAUSE;
      pip.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE, status);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `updatePiPControlStatus failed: ${JSON.stringify(e)}`);
    }
  }

  private async releaseSystemPip(): Promise<void> {
    const pip = this.pipController;
    this.pipController = undefined;
    this.isSystemPipActive = false;
    this.pipRestoring = false;
    if (pip !== undefined) {
      try {
        pip.setAutoStartEnabled(false);
        pip.off('stateChange');
        pip.off('controlPanelActionEvent');
        await pip.stopPiP();
      } catch (e) {
        // ignore if already stopped
      }
    }
  }

  private async initOrUpdateSystemPip(): Promise<void> {
    if (!this.inAppVideoVisible || this.useWebFallback) {
      return;
    }
    try {
      if (!PiPWindow.isPiPEnabled()) {
        return;
      }
      if (this.pipController !== undefined) {
        this.pipController.setAutoStartEnabled(this.isVideoPlaying);
        try {
          this.pipController.updateContentSize(this.videoContentWidth, this.videoContentHeight);
        } catch (_) {
        }
        this.syncPipPlaybackState();
        return;
      }
      const config: PiPWindow.PiPConfiguration = {
        context: this.context,
        componentController: this.xComponentController,
        templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
        contentWidth: this.videoContentWidth,
        contentHeight: this.videoContentHeight
      };
      const ctrl = await PiPWindow.create(config);
      this.pipController = ctrl;
      ctrl.setAutoStartEnabled(this.isVideoPlaying);
      ctrl.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
        hilog.info(DOMAIN, TAG, `PiP stateChange: ${state}, reason=${reason}`);
        if (state === PiPWindow.PiPState.ABOUT_TO_START) {
          this.pipRestoring = false;
          this.isSystemPipActive = true;
          this.controlsVisible = false;
          this.showMoreSheet = false;
          this.stopGravitySensor();
          this.setLandscapeMultiWindowEnabled(false);
        } else if (state === PiPWindow.PiPState.STARTED) {
          this.pipRestoring = false;
          this.isSystemPipActive = true;
          this.controlsVisible = false;
          this.showMoreSheet = false;
          this.syncPipPlaybackState();
          if (this.isPlayerFullscreen) {
            this.isPlayerFullscreen = false;
            this.manualFullscreenLock = false;
          }
          this.applyPlayerWindowMode(window.Orientation.UNSPECIFIED, false);
        } else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
          this.pipRestoring = true;
          this.isSystemPipActive = false;
          this.controlsVisible = true;
          if (this.sensorRotation && !this.isSystemMultiWindow()) {
            this.startGravitySensor();
          }
          this.syncLandscapeMultiWindow();
          this.scheduleHideOverlay();
        } else if (state === PiPWindow.PiPState.ABOUT_TO_STOP) {
          if (!this.pipRestoring) {
            this.isSystemPipActive = false;
          }
        } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
          const wasRestoring = this.pipRestoring;
          this.pipRestoring = false;
          this.isSystemPipActive = false;
          const finishedCtrl = this.pipController;
          this.pipController = undefined;
          if (finishedCtrl !== undefined) {
            try {
              finishedCtrl.off('stateChange');
              finishedCtrl.off('controlPanelActionEvent');
            } catch (_) {
            }
          }
          if (wasRestoring) {
            this.controlsVisible = true;
            this.syncLandscapeMultiWindow();
            this.scheduleHideOverlay();
            setTimeout(() => {
              if (this.inAppVideoVisible && !this.useWebFallback && !this.isSystemPipActive) {
                this.initOrUpdateSystemPip();
              }
            }, 200);
          } else if (this.inAppVideoVisible) {
            this.closeVideoOverlay();
          }
        }
      });
      ctrl.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) => {
        if (event === 'playbackStateChanged') {
          if (status === 1) {
            this.manualTargetPlaying = true;
            this.lastManualPlayToggleMs = Date.now();
            this.isVideoPlaying = true;
            this.avPlayer?.play();
          } else if (status === 0) {
            this.manualTargetPlaying = false;
            this.lastManualPlayToggleMs = Date.now();
            this.isVideoPlaying = false;
            this.avPlayer?.pause();
          } else {
            this.togglePlayPause();
            return;
          }
          ctrl.setAutoStartEnabled(this.isVideoPlaying);
          this.syncPipPlaybackState();
        }
      });
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `initOrUpdateSystemPip failed: ${JSON.stringify(e)}`);
    }
  }

  private async triggerPipOrMiniWindow(): Promise<void> {
    if (!this.useWebFallback && this.avPlayer !== undefined) {
      try {
        if (PiPWindow.isPiPEnabled()) {
          await this.setLandscapeMultiWindowEnabled(false);
          this.manualFullscreenLock = false;
          this.isPlayerFullscreen = false;
          this.isPlayerMiniWindow = false;
          await this.applyPlayerWindowMode(window.Orientation.UNSPECIFIED, false);
          await this.initOrUpdateSystemPip();
          if (this.pipController !== undefined) {
            try {
              this.pipController.updateContentSize(this.videoContentWidth, this.videoContentHeight);
            } catch (_) {
            }
            this.pipRestoring = false;
            this.isSystemPipActive = true;
            this.controlsVisible = false;
            this.showMoreSheet = false;
            await this.pipController.startPiP();
            return;
          }
        }
      } catch (e) {
        this.isSystemPipActive = false;
        this.syncLandscapeMultiWindow();
        hilog.warn(DOMAIN, TAG, `startPiP failed, fallback to in-app mini: ${JSON.stringify(e)}`);
      }
    }
    this.enterMiniWindow();
  }

  private async startAvPlayerPlayback(targetUrl: string): Promise<void> {
    if (!this.inAppVideoVisible || this.useWebFallback || targetUrl.length === 0 || this.xComponentSurfaceId.length === 0) {
      return;
    }
    this.videoLoading = true;
    await this.releaseAvPlayer();
    try {
      const player = await media.createAVPlayer();
      if (!this.inAppVideoVisible || this.useWebFallback) {
        await player.release();
        return;
      }
      this.avPlayer = player;
      this.clearPrepareWatchdog();
      this.prepareWatchdogTimer = setTimeout(() => {
        this.prepareWatchdogTimer = -1;
        if (this.avPlayer === player && this.videoLoading && !this.useWebFallback) {
          hilog.warn(DOMAIN, TAG, 'AVPlayer prepare watchdog timeout (8s), switching to next stream or web');
          this.switchNextStreamOrWeb();
        }
      }, 8000);
      player.on('videoSizeChange', (width: number, height: number) => {
        if (this.avPlayer !== player) return;
        if (width > 0 && height > 0) {
          this.videoContentWidth = width;
          this.videoContentHeight = height;
          this.videoAspectRatio = width / height;
          try {
            this.pipController?.updateContentSize(width, height);
          } catch (_) {
          }
          this.syncLandscapeMultiWindow();
        }
      });
      player.on('timeUpdate', (timeMs: number) => {
        if (this.avPlayer !== player || this.isSeeking) return;
        this.videoCurrentTime = Math.max(0, Math.floor(timeMs / 1000));
      });
      player.on('error', (err: BusinessError) => {
        if (this.avPlayer !== player) return;
        this.clearPrepareWatchdog();
        hilog.warn(DOMAIN, TAG, `AVPlayer error ${err.code}: ${err.message}`);
        this.switchNextStreamOrWeb();
      });
      player.on('stateChange', async (state: string) => {
        if (this.avPlayer !== player) return;
        if (state === 'initialized') {
          if (this.xComponentSurfaceId.length > 0) {
            player.surfaceId = this.xComponentSurfaceId;
          }
          try {
            await player.prepare();
          } catch (prepErr) {
            this.clearPrepareWatchdog();
            hilog.warn(DOMAIN, TAG, `AVPlayer prepare failed: ${JSON.stringify(prepErr)}`);
            this.switchNextStreamOrWeb();
          }
        } else if (state === 'prepared') {
          this.clearPrepareWatchdog();
          this.videoDuration = player.duration > 0 ? Math.floor(player.duration / 1000) : 0;
          this.videoLoading = false;
          try {
            player.setSpeed(this.avSpeed);
          } catch (speedErr) {
            hilog.warn(DOMAIN, TAG, `setSpeed failed: ${JSON.stringify(speedErr)}`);
          }
          try {
            await player.play();
            await this.initOrUpdateSystemPip();
          } catch (playErr) {
            hilog.warn(DOMAIN, TAG, `AVPlayer play failed: ${JSON.stringify(playErr)}`);
          }
        } else if (state === 'playing') {
          this.clearPrepareWatchdog();
          this.videoLoading = false;
          if (Date.now() - this.lastManualPlayToggleMs < 350 && !this.manualTargetPlaying) {
            return;
          }
          this.isVideoPlaying = true;
          this.manualTargetPlaying = true;
          this.pipController?.setAutoStartEnabled(true);
          this.syncPipPlaybackState();
          this.scheduleHideOverlay();
        } else if (state === 'paused') {
          if (Date.now() - this.lastManualPlayToggleMs < 350 && this.manualTargetPlaying) {
            return;
          }
          this.isVideoPlaying = false;
          this.manualTargetPlaying = false;
          this.pipController?.setAutoStartEnabled(false);
          this.syncPipPlaybackState();
          if (!this.isSystemPipActive) {
            this.controlsVisible = true;
          }
        } else if (state === 'completed') {
          this.isVideoPlaying = false;
          this.manualTargetPlaying = false;
          this.pipController?.setAutoStartEnabled(false);
          this.syncPipPlaybackState();
          this.controlsVisible = true;
        }
      });

      let sourceAssigned = false;
      try {
        const headers: Record<string, string> = {
          'Referer': 'https://classroom.zju.edu.cn/',
          'Origin': 'https://classroom.zju.edu.cn',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
        };
        if (this.inAppVideoToken.length > 0) {
          const phpTk = this.buildPhpSerializedToken(this.inAppVideoToken);
          headers['Cookie'] = `_token=${phpTk}; token=${this.inAppVideoToken}`;
          headers['Authorization'] = `Bearer ${this.inAppVideoToken}`;
        }
        const mediaSource: media.MediaSource = media.createMediaSourceWithUrl(targetUrl, headers);
        const strategy: media.PlaybackStrategy = { preferredBufferDuration: 6 };
        await player.setMediaSource(mediaSource, strategy);
        sourceAssigned = true;
      } catch (srcErr) {
        hilog.warn(DOMAIN, TAG, `createMediaSourceWithUrl failed, using url: ${JSON.stringify(srcErr)}`);
      }
      if (!sourceAssigned) {
        player.url = targetUrl;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `startAvPlayerPlayback exception: ${JSON.stringify(e)}`);
      this.switchNextStreamOrWeb();
    }
  }

  private closeVideoOverlay(): void {
    this.manualFullscreenLock = false;
    this.isPlayerFullscreen = false;
    this.isPlayerMiniWindow = false;
    this.isSystemPipActive = false;
    this.pipRestoring = false;
    this.showMoreSheet = false;
    this.miniOffsetX = 0;
    this.miniOffsetY = 0;
    this.xComponentSurfaceId = '';
    this.stopGravitySensor();
    this.clearOverlayTimers();
    this.setLandscapeMultiWindowEnabled(false);
    this.releaseSystemPip();
    this.releaseAvPlayer();
    this.inAppVideoVisible = false;
    this.applyPlayerWindowMode(window.Orientation.UNSPECIFIED, false);
  }

  private enterLandscapeFullscreen(): void {
    this.manualFullscreenLock = true;
    this.isPlayerMiniWindow = false;
    this.isPlayerFullscreen = true;
    this.showMoreSheet = false;
    this.applyPlayerWindowMode(window.Orientation.LANDSCAPE, true);
    if (this.sensorRotation && !this.isSystemMultiWindow()) {
      this.startGravitySensor();
    }
    this.scheduleHideOverlay();
  }

  private exitLandscapeFullscreen(): void {
    this.manualFullscreenLock = false;
    this.isPlayerFullscreen = false;
    this.showMoreSheet = false;
    this.applyPlayerWindowMode(this.isSystemMultiWindow() ? window.Orientation.UNSPECIFIED : window.Orientation.PORTRAIT, false);
    this.scheduleHideOverlay();
  }

  private enterMiniWindow(): void {
    this.manualFullscreenLock = false;
    this.isPlayerFullscreen = false;
    this.isPlayerMiniWindow = true;
    this.showMoreSheet = false;
    this.stopGravitySensor();
    this.clearOverlayTimers();
    this.applyPlayerWindowMode(this.isSystemMultiWindow() ? window.Orientation.UNSPECIFIED : window.Orientation.PORTRAIT, false);
  }

  private togglePlayPause(): void {
    if (this.useWebFallback || this.avPlayer === undefined) {
      return;
    }
    const nextPlaying = !this.isVideoPlaying;
    this.lastManualPlayToggleMs = Date.now();
    this.manualTargetPlaying = nextPlaying;
    this.isVideoPlaying = nextPlaying;
    if (this.hideOverlayTimer !== -1) {
      clearTimeout(this.hideOverlayTimer);
      this.hideOverlayTimer = -1;
    }
    try {
      this.pipController?.setAutoStartEnabled(nextPlaying);
      this.syncPipPlaybackState();
      if (nextPlaying) {
        this.avPlayer.play();
        this.scheduleHideOverlay();
      } else {
        this.avPlayer.pause();
        if (!this.isSystemPipActive) {
          this.controlsVisible = true;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `togglePlayPause failed: ${JSON.stringify(e)}`);
    }
  }

  private setVideoSpeedPreset(label: string, speed: media.PlaybackSpeed): void {
    this.avSpeed = speed;
    this.videoSpeedLabel = label;
    try {
      if (this.avPlayer !== undefined) {
        this.avPlayer.setSpeed(speed);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `setSpeed failed: ${JSON.stringify(e)}`);
    }
    this.showHudMessage(`${label} 倍速`);
    this.scheduleHideOverlay();
  }

  private seekRelativeSeconds(deltaSec: number): void {
    if (this.useWebFallback || this.avPlayer === undefined || this.videoDuration <= 0) {
      return;
    }
    const targetSec = Math.max(0, Math.min(this.videoDuration, this.videoCurrentTime + deltaSec));
    this.videoCurrentTime = targetSec;
    try {
      this.avPlayer.seek(Math.floor(targetSec * 1000), media.SeekMode.SEEK_PREV_SYNC);
      this.showHudMessage(deltaSec > 0 ? `快进 ${deltaSec} 秒` : `快退 ${Math.abs(deltaSec)} 秒`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `seekRelativeSeconds failed: ${JSON.stringify(e)}`);
    }
    this.scheduleHideOverlay();
  }

  private buildPhpSerializedToken(token: string): string {
    const trimmed = token.trim();
    if (trimmed.length === 0) {
      return '';
    }
    return encodeURIComponent(`a:2:{i:0;s:6:"_token";i:1;s:${trimmed.length}:"${trimmed}";}`);
  }

  private preConfigureWebCookies(): void {
    if (this.inAppVideoToken.length === 0) {
      return;
    }
    try {
      const phpTk = this.buildPhpSerializedToken(this.inAppVideoToken);
      const rawTk = this.inAppVideoToken.trim();
      const hosts = [
        'https://classroom.zju.edu.cn',
        'https://yjapi.cmc.zju.edu.cn',
        'https://tgmedia.cmc.zju.edu.cn',
        'https://livingroom.cmc.zju.edu.cn'
      ];
      for (let i = 0; i < hosts.length; i++) {
        webview.WebCookieManager.configCookieSync(hosts[i], `_token=${phpTk}; Path=/`);
        webview.WebCookieManager.configCookieSync(hosts[i], `_token=${phpTk}; Domain=.zju.edu.cn; Path=/`);
        webview.WebCookieManager.configCookieSync(hosts[i], `_token=${phpTk}; Domain=classroom.zju.edu.cn; Path=/`);
        webview.WebCookieManager.configCookieSync(hosts[i], `token=${rawTk}; Path=/`);
        webview.WebCookieManager.configCookieSync(hosts[i], `token=${rawTk}; Domain=.zju.edu.cn; Path=/`);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `preConfigureWebCookies failed: ${JSON.stringify(err)}`);
    }
  }

  private injectWebTokenJs(): void {
    const rawTk = this.inAppVideoToken.trim();
    const safeTk = rawTk
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'")
      .replace(/\n/g, '');
    const phpTk = this.buildPhpSerializedToken(rawTk);
    const js = `try{` +
      (safeTk.length > 0
        ? `localStorage.setItem('token','${safeTk}');localStorage.setItem('_token','${safeTk}');` +
          `document.cookie='_token=${phpTk};path=/;domain=.zju.edu.cn';` +
          `document.cookie='_token=${phpTk};path=/';` +
          `document.cookie='token=${safeTk};path=/;domain=.zju.edu.cn';` +
          `document.cookie='token=${safeTk};path=/';`
        : '') +
      `if(!document.getElementById('celechron_zy_fullscreen_css')){` +
        `var st=document.createElement('style');st.id='celechron_zy_fullscreen_css';` +
        `st.innerHTML='html,body,#app{background:#000 !important;margin:0 !important;padding:0 !important;overflow:hidden !important;width:100vw !important;height:100vh !important;}' +` +
        `'.header-wrapper,.living-header,.living-right,.right-wrapper,.nav-bar,.catalog-wrapper,.sidebar-wrapper,.chat-wrapper,.danmu-send-wrap{display:none !important;}' +` +
        `'.living-room-wrapper,.living-content,.left-wrapper,.player-wrapper,.cmc-player-container,#cmc_player_container{position:fixed !important;left:0 !important;top:0 !important;right:0 !important;bottom:0 !important;width:100vw !important;height:100vh !important;max-width:100vw !important;max-height:100vh !important;margin:0 !important;padding:0 !important;z-index:9999 !important;background:#000 !important;}' +` +
        `'video{width:100% !important;height:100% !important;object-fit:contain !important;background:#000 !important;}';` +
        `document.head.appendChild(st);` +
      `}` +
      `setTimeout(function(){try{window.dispatchEvent(new Event('resize'));var v=document.querySelector('video');if(v&&v.paused){v.play().catch(function(){});}}catch(e){}},600);` +
      `}catch(e){}`;
    try {
      this.webController.runJavaScript(js);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `runJavaScript failed: ${JSON.stringify(e)}`);
    }
  }

  private appendTokenParam(rawUrl: string): string {
    const trimmed = rawUrl.trim();
    const tk = this.inAppVideoToken.trim();
    if (trimmed.length === 0 || tk.length === 0) {
      return trimmed;
    }
    if (trimmed.indexOf('token=') >= 0) {
      return trimmed;
    }
    const sep = trimmed.indexOf('?') >= 0 ? '&' : '?';
    return `${trimmed}${sep}token=${encodeURIComponent(tk)}`;
  }

  private webFallbackTarget(): string {
    if (this.inAppVideoLivingroomUrl.length > 0) {
      return this.appendTokenParam(this.inAppVideoLivingroomUrl);
    }
    return !isDirectStreamUrl(this.inAppVideoUrl) ? this.appendTokenParam(this.inAppVideoUrl) : '';
  }

  private switchNextStreamOrWeb(): void {
    this.clearPrepareWatchdog();
    const nextIdx = this.activeStreamIndex + 1;
    if (nextIdx < this.videoStreams.length) {
      this.activeStreamIndex = nextIdx;
      this.activeVideoUrl = this.videoStreams[nextIdx].url;
      this.useWebFallback = false;
      this.startAvPlayerPlayback(this.activeVideoUrl);
      return;
    }
    if (this.webFallbackTarget().length > 0) {
      this.preConfigureWebCookies();
      this.useWebFallback = true;
      this.videoLoading = false;
      this.controlsVisible = true;
      this.releaseSystemPip();
      this.releaseAvPlayer();
    }
  }

  private cycleVideoSpeed(): void {
    if (this.videoSpeedLabel === '0.75x') {
      this.setVideoSpeedPreset('1.0x', media.PlaybackSpeed.SPEED_FORWARD_1_00_X);
    } else if (this.videoSpeedLabel === '1.0x') {
      this.setVideoSpeedPreset('1.25x', media.PlaybackSpeed.SPEED_FORWARD_1_25_X);
    } else if (this.videoSpeedLabel === '1.25x') {
      this.setVideoSpeedPreset('1.75x', media.PlaybackSpeed.SPEED_FORWARD_1_75_X);
    } else if (this.videoSpeedLabel === '1.75x') {
      this.setVideoSpeedPreset('2.0x', media.PlaybackSpeed.SPEED_FORWARD_2_00_X);
    } else {
      this.setVideoSpeedPreset('0.75x', media.PlaybackSpeed.SPEED_FORWARD_0_75_X);
    }
  }

  private getMiniWindowWidth(): number {
    return this.videoAspectRatio >= 1.0 ? 256 : 144;
  }

  private getMiniWindowHeight(): number {
    if (this.videoAspectRatio >= 1.0) {
      return Math.max(120, Math.min(200, Math.round(256 / this.videoAspectRatio)));
    }
    return Math.max(160, Math.min(260, Math.round(144 / this.videoAspectRatio)));
  }

  private getXComponentWidth(): Length {
    if (this.isSystemPipActive) {
      return 1;
    }
    if (this.playerContainerW > 0 && this.playerContainerH > 0 &&
        this.playerContainerAspect > this.videoAspectRatio) {
      return Math.round(this.playerContainerH * this.videoAspectRatio);
    }
    return '100%';
  }

  private getXComponentHeight(): Length {
    if (this.isSystemPipActive) {
      return 1;
    }
    if (this.playerContainerW > 0 && this.playerContainerH > 0 &&
        this.playerContainerAspect > this.videoAspectRatio) {
      return '100%';
    }
    if (this.playerContainerW > 0) {
      return Math.round(this.playerContainerW / this.videoAspectRatio);
    }
    return Math.round(360 / this.videoAspectRatio);
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

  private scaleSvgPath(cmd: string, sizeVp: number): string {
    const factor: number = vp2px(sizeVp) / 24.0;
    return cmd.replace(/-?\d+(\.\d+)?/g, (m: string): string => {
      return (parseFloat(m) * factor).toFixed(2);
    });
  }

  @Builder
  PlayerVectorIcon(commands: string, filled: boolean, size: number, colorStr: string) {
    Path()
      .width(size)
      .height(size)
      .commands(this.scaleSvgPath(commands, size))
      .fill(filled ? colorStr : '#00000000')
      .stroke(filled ? '#00000000' : colorStr)
      .strokeWidth(2.4)
      .strokeLineCap(LineCapStyle.Round)
      .strokeLineJoin(LineJoinStyle.Round)
  }

  @Builder
  PlayerPipIcon(size: number, colorStr: string) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column()
        .width(size)
        .height(Math.round(size * 0.78))
        .border({ width: 2.0, color: colorStr, radius: 3 })
      Column()
        .width(Math.round(size * 0.48))
        .height(Math.round(size * 0.38))
        .borderRadius(2)
        .backgroundColor(colorStr)
        .margin({ right: 2, bottom: 2 })
    }
    .width(size)
    .height(Math.round(size * 0.78))
  }

  @Builder
  PlayerMoreDotsIcon(colorStr: string) {
    Row({ space: 5 }) {
      Circle({ width: 6, height: 6 }).fill(colorStr)
      Circle({ width: 6, height: 6 }).fill(colorStr)
      Circle({ width: 6, height: 6 }).fill(colorStr)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  VideoPlayerMoreSheet() {
    Column({ space: 14 }) {
      Row() {
        Text('播放控制与设置')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
        Text(this.sensorRotation ? '重力旋屏：已开启' : '重力旋屏：已锁定')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.sensorRotation ? '#FF6699' : '#CCFFFFFF')
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(this.sensorRotation ? '#33FF6699' : '#26FFFFFF')
          .onClick(() => {
            this.sensorRotation = !this.sensorRotation;
            if (this.sensorRotation) {
              this.startGravitySensor();
              this.showHudMessage('已开启重力旋屏');
            } else {
              this.stopGravitySensor();
              this.showHudMessage('已锁定方向');
            }
          })
      }
      .width('100%')

      if (!this.useWebFallback) {
        Text('播放倍速')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#B3FFFFFF')
        Row({ space: 8 }) {
          this.SpeedPresetChip('0.75x', media.PlaybackSpeed.SPEED_FORWARD_0_75_X)
          this.SpeedPresetChip('1.0x', media.PlaybackSpeed.SPEED_FORWARD_1_00_X)
          this.SpeedPresetChip('1.25x', media.PlaybackSpeed.SPEED_FORWARD_1_25_X)
          this.SpeedPresetChip('1.75x', media.PlaybackSpeed.SPEED_FORWARD_1_75_X)
          this.SpeedPresetChip('2.0x', media.PlaybackSpeed.SPEED_FORWARD_2_00_X)
        }
      }

      if (!this.useWebFallback && this.videoStreams.length > 1) {
        Text('视频线路切换')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#B3FFFFFF')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.videoStreams, (streamItem: StreamSource, idx: number) => {
            Text(streamItem.label)
              .fontSize(13.5)
              .fontColor(this.activeStreamIndex === idx ? '#FF6699' : Color.White)
              .fontWeight(this.activeStreamIndex === idx ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius(10)
              .backgroundColor(this.activeStreamIndex === idx ? '#33FF6699' : '#26FFFFFF')
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.activeStreamIndex = idx;
                this.activeVideoUrl = streamItem.url;
                this.showMoreSheet = false;
                this.showHudMessage(`已切换至 ${streamItem.label}`);
                this.startAvPlayerPlayback(streamItem.url);
              })
          }, (streamItem: StreamSource, idx: number) => `${idx}_${streamItem.url}`)
        }
      }

      Row({ space: 10 }) {
        if (!this.useWebFallback && this.webFallbackTarget().length > 0) {
          Text('切换网页端播放器')
            .fontSize(13.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(10)
            .backgroundColor('#4D0A84FF')
            .onClick(() => {
              this.preConfigureWebCookies();
              this.useWebFallback = true;
              this.showMoreSheet = false;
              this.controlsVisible = true;
              this.releaseSystemPip();
              this.releaseAvPlayer();
            })
        } else if (this.useWebFallback && (this.videoStreams.length > 0 || isDirectStreamUrl(this.inAppVideoUrl))) {
          Text('返回原生流播放器')
            .fontSize(13.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .borderRadius(10)
            .backgroundColor('#4DFF6699')
            .onClick(() => {
              this.useWebFallback = false;
              this.showMoreSheet = false;
              this.videoLoading = true;
              this.scheduleHideOverlay();
              if (this.xComponentSurfaceId.length > 0) {
                this.startAvPlayerPlayback(this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl);
              }
            })
        }

        Text('小窗悬浮播放')
          .fontSize(13.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(10)
          .backgroundColor('#33FFFFFF')
          .onClick(() => {
            this.showMoreSheet = false;
            this.triggerPipOrMiniWindow();
          })
      }
    }
    .width(320)
    .padding(16)
    .borderRadius(16)
    .backgroundColor('#F01A1A1E')
    .border({ width: 0.8, color: '#33FFFFFF' })
    .shadow({ radius: 24, color: '#99000000', offsetX: 0, offsetY: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SpeedPresetChip(label: string, spd: media.PlaybackSpeed) {
    Text(label)
      .fontSize(13.5)
      .fontColor(this.videoSpeedLabel === label ? '#FF6699' : Color.White)
      .fontWeight(this.videoSpeedLabel === label ? FontWeight.Bold : FontWeight.Medium)
      .padding({ left: 11, right: 11, top: 7, bottom: 7 })
      .borderRadius(10)
      .backgroundColor(this.videoSpeedLabel === label ? '#33FF6699' : '#26FFFFFF')
      .onClick(() => {
        this.setVideoSpeedPreset(label, spd);
        this.showMoreSheet = false;
      })
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
        Stack({ alignContent: this.isPlayerMiniWindow ? Alignment.BottomEnd : Alignment.Center }) {
          Stack({ alignContent: Alignment.Center }) {
            // 底层：统一 XComponent（支持应用外系统 PiPWindow + 应用内无重加载切小窗）或 WebView
            if (this.useWebFallback && this.webFallbackTarget().length > 0) {
              Column() {
                if (!this.isPlayerMiniWindow) {
                  Row({ space: 10 }) {
                    Stack() {
                      this.PlayerVectorIcon('M15 4.5 L7.5 12 L15 19.5', false, 26, '#FFFFFF')
                    }
                    .width(46)
                    .height(46)
                    .borderRadius(23)
                    .backgroundColor('#4DFFFFFF')
                    .onClick(() => {
                      if (this.isPlayerFullscreen) {
                        this.exitLandscapeFullscreen();
                      } else {
                        this.closeVideoOverlay();
                      }
                    })

                    Text(this.inAppVideoTitle)
                      .fontSize(15.5)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    if (this.videoStreams.length > 0 || isDirectStreamUrl(this.inAppVideoUrl)) {
                      Row({ space: 5 }) {
                        Text('原生流')
                          .fontSize(13)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                      }
                      .height(38)
                      .padding({ left: 12, right: 12 })
                      .borderRadius(19)
                      .backgroundColor('#CCFF6699')
                      .alignItems(VerticalAlign.Center)
                      .onClick(() => {
                        this.useWebFallback = false;
                        this.showMoreSheet = false;
                        this.videoLoading = true;
                        this.scheduleHideOverlay();
                        if (this.xComponentSurfaceId.length > 0) {
                          this.startAvPlayerPlayback(this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl);
                        }
                      })
                    }

                    Row({ space: 5 }) {
                      if (this.isPlayerFullscreen) {
                        this.PlayerVectorIcon(
                          'M9 3.5 L9 9 L3.5 9 M15 3.5 L15 9 L20.5 9 M15 20.5 L15 15 L20.5 15 M9 20.5 L9 15 L3.5 15',
                          false,
                          18,
                          '#FFFFFF'
                        )
                      } else {
                        this.PlayerVectorIcon(
                          'M3.5 9 L3.5 3.5 L9 3.5 M15 3.5 L20.5 3.5 L20.5 9 M20.5 15 L20.5 20.5 L15 20.5 M9 20.5 L3.5 20.5 L3.5 15',
                          false,
                          18,
                          '#FFFFFF'
                        )
                      }
                      Text(this.isPlayerFullscreen ? '竖屏' : '横屏')
                        .fontSize(13)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                    }
                    .height(38)
                    .padding({ left: 12, right: 12 })
                    .borderRadius(19)
                    .backgroundColor('#33FFFFFF')
                    .alignItems(VerticalAlign.Center)
                    .onClick(() => {
                      if (this.isPlayerFullscreen) {
                        this.exitLandscapeFullscreen();
                      } else {
                        this.enterLandscapeFullscreen();
                      }
                    })

                    Stack() {
                      this.PlayerMoreDotsIcon('#FFFFFF')
                    }
                    .width(46)
                    .height(46)
                    .borderRadius(23)
                    .backgroundColor('#33FFFFFF')
                    .onClick(() => {
                      this.showMoreSheet = !this.showMoreSheet;
                    })
                  }
                  .width('100%')
                  .padding({
                    left: Math.max(12, this.safeLeft + 8),
                    right: Math.max(12, this.safeRight + 8),
                    top: this.isPlayerFullscreen ? 8 : Math.max(10, this.safeTop + 4),
                    bottom: 8
                  })
                  .backgroundColor('#141418')
                }

                Web({ src: this.webFallbackTarget(), controller: this.webController })
                  .width('100%')
                  .layoutWeight(1)
                  .backgroundColor(Color.Black)
                  .javaScriptAccess(true)
                  .domStorageAccess(true)
                  .mediaPlayGestureAccess(false)
                  .mixedMode(MixedMode.All)
                  .onControllerAttached(() => {
                    this.preConfigureWebCookies();
                    try {
                      this.webController.setCustomUserAgent(
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
                      );
                    } catch (uaErr) {
                      hilog.warn(DOMAIN, TAG, `setCustomUserAgent failed: ${JSON.stringify(uaErr)}`);
                    }
                  })
                  .onSslErrorEventReceive((event) => {
                    try {
                      event.handler.handleConfirm();
                    } catch (sslErr) {
                      hilog.warn(DOMAIN, TAG, `handleConfirm ssl failed: ${JSON.stringify(sslErr)}`);
                    }
                  })
                  .onPageBegin(() => {
                    this.injectWebTokenJs();
                  })
                  .onPageEnd(() => {
                    this.injectWebTokenJs();
                  })
              }
              .width('100%')
              .height('100%')
            } else {
              XComponent({
                id: 'zhiyunPlayerXComponent',
                type: XComponentType.SURFACE,
                controller: this.xComponentController
              })
                .width(this.getXComponentWidth())
                .height(this.getXComponentHeight())
                .aspectRatio(this.isSystemPipActive ? 1 : this.videoAspectRatio)
                .hitTestBehavior(this.isSystemPipActive ? HitTestMode.None : HitTestMode.Default)
                .onLoad(() => {
                  this.xComponentSurfaceId = this.xComponentController.getXComponentSurfaceId();
                  const target = this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl;
                  this.startAvPlayerPlayback(target);
                })
                .gesture(
                  GestureGroup(
                    GestureMode.Exclusive,
                    TapGesture({ count: 2 })
                      .onAction((event: GestureEvent) => {
                        if (this.isSystemPipActive) {
                          return;
                        }
                        if (this.isPlayerMiniWindow) {
                          this.isPlayerMiniWindow = false;
                          this.enterLandscapeFullscreen();
                          return;
                        }
                        const tapX = event.fingerList.length > 0 ? event.fingerList[0].localX : 0;
                        const w = this.playerContainerW > 0 ? this.playerContainerW : 360;
                        if (this.videoDuration > 0 && tapX > 0 && tapX < w * 0.32) {
                          this.seekRelativeSeconds(-10);
                        } else if (this.videoDuration > 0 && tapX > w * 0.68) {
                          this.seekRelativeSeconds(10);
                        } else {
                          this.togglePlayPause();
                        }
                      }),
                    TapGesture({ count: 1 })
                      .onAction(() => {
                        if (this.isSystemPipActive) {
                          return;
                        }
                        if (this.isPlayerMiniWindow) {
                          this.isPlayerMiniWindow = false;
                          this.enterLandscapeFullscreen();
                          return;
                        }
                        if (this.showMoreSheet) {
                          this.showMoreSheet = false;
                          return;
                        }
                        this.controlsVisible = !this.controlsVisible;
                        if (this.controlsVisible) {
                          this.scheduleHideOverlay();
                        }
                      })
                  )
                )
            }

            // 应用内悬浮小窗仅展示右上角 2 个大号清晰图标钮
            if (this.isPlayerMiniWindow) {
              Column() {
                Row({ space: 10 }) {
                  Stack() {
                    this.PlayerVectorIcon(
                      'M3.5 9 L3.5 3.5 L9 3.5 M15 3.5 L20.5 3.5 L20.5 9 M20.5 15 L20.5 20.5 L15 20.5 M9 20.5 L3.5 20.5 L3.5 15',
                      false,
                      22,
                      '#FFFFFF'
                    )
                  }
                  .width(42)
                  .height(42)
                  .borderRadius(21)
                  .backgroundColor('#B3000000')
                  .onClick(() => {
                    this.isPlayerMiniWindow = false;
                    this.enterLandscapeFullscreen();
                  })

                  Stack() {
                    this.PlayerVectorIcon('M6 6 L18 18 M18 6 L6 18', false, 22, '#FFFFFF')
                  }
                  .width(42)
                  .height(42)
                  .borderRadius(21)
                  .backgroundColor('#B3000000')
                  .onClick(() => {
                    this.closeVideoOverlay();
                  })
                }
              }
              .width('100%')
              .height('100%')
              .padding({ top: 8, right: 8 })
              .alignItems(HorizontalAlign.End)
              .justifyContent(FlexAlign.Start)
              .hitTestBehavior(HitTestMode.Transparent)
            }

            // 中央加载/播放提示与 HUD（非应用内小窗且非系统画中画时展示）
            if (!this.isPlayerMiniWindow && !this.isSystemPipActive) {
              if (!this.useWebFallback && this.videoLoading) {
                Column({ space: 10 }) {
                  LoadingProgress()
                    .width(48)
                    .height(48)
                    .color('#FF6699')
                  Text('正在连接课堂流...')
                    .fontSize(13)
                    .fontColor('#CCFFFFFF')
                }
                .padding(16)
                .borderRadius(16)
                .backgroundColor('#80000000')
              }

              if (!this.useWebFallback && this.controlsVisible && !this.videoLoading) {
                Row({ space: this.isCompactSmallWindow() ? 16 : 28 }) {
                  if (this.videoDuration > 0) {
                    Stack() {
                      Text('-10s')
                        .fontSize(this.isCompactSmallWindow() ? 12 : 14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                    }
                    .width(this.isCompactSmallWindow() ? 44 : 56)
                    .height(this.isCompactSmallWindow() ? 44 : 56)
                    .borderRadius(this.isCompactSmallWindow() ? 22 : 28)
                    .backgroundColor('#80000000')
                    .border({ width: 0.8, color: '#40FFFFFF' })
                    .onClick(() => {
                      this.seekRelativeSeconds(-10);
                    })
                  }

                  Stack() {
                    if (this.isVideoPlaying) {
                      this.PlayerVectorIcon(
                        'M6 4.5 L10 4.5 L10 19.5 L6 19.5 Z M14 4.5 L18 4.5 L18 19.5 L14 19.5 Z',
                        true,
                        this.isCompactSmallWindow() ? 30 : 38,
                        '#FFFFFF'
                      )
                    } else {
                      this.PlayerVectorIcon(
                        'M7 4.2 L20.2 12 L7 19.8 Z',
                        true,
                        this.isCompactSmallWindow() ? 30 : 38,
                        '#FFFFFF'
                      )
                    }
                  }
                  .width(this.isCompactSmallWindow() ? 58 : 76)
                  .height(this.isCompactSmallWindow() ? 58 : 76)
                  .borderRadius(this.isCompactSmallWindow() ? 29 : 38)
                  .backgroundColor('#88000000')
                  .border({ width: 1.0, color: '#4DFFFFFF' })
                  .onClick(() => {
                    this.togglePlayPause();
                  })

                  if (this.videoDuration > 0) {
                    Stack() {
                      Text('+10s')
                        .fontSize(this.isCompactSmallWindow() ? 12 : 14)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(Color.White)
                    }
                    .width(this.isCompactSmallWindow() ? 44 : 56)
                    .height(this.isCompactSmallWindow() ? 44 : 56)
                    .borderRadius(this.isCompactSmallWindow() ? 22 : 28)
                    .backgroundColor('#80000000')
                    .border({ width: 0.8, color: '#40FFFFFF' })
                    .onClick(() => {
                      this.seekRelativeSeconds(10);
                    })
                  }
                }
                .alignItems(VerticalAlign.Center)
              }

              if (this.hudText.length > 0) {
                Column() {
                  Text(this.hudText)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                    .borderRadius(20)
                    .backgroundColor('#D91C1C1E')
                }
                .width('100%')
                .height('100%')
                .padding({ top: (this.isPlayerFullscreen ? 18 : this.safeTop + 16) + 60 })
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Start)
                .hitTestBehavior(HitTestMode.None)
              }

              // 原生流播放器悬浮渐隐工具栏（顶部 + 底部双行，参考 Bilibili/主流移动端播放器设计）
              if (!this.useWebFallback && this.controlsVisible) {
                Column() {
                  // 顶部渐变控制栏：返回 + 标题 + 小窗胶囊 + 更多
                  Row({ space: 10 }) {
                    Stack() {
                      this.PlayerVectorIcon('M15 4.5 L7.5 12 L15 19.5', false, 26, '#FFFFFF')
                    }
                    .width(48)
                    .height(48)
                    .borderRadius(24)
                    .backgroundColor('#66000000')
                    .onClick(() => {
                      if (this.isPlayerFullscreen) {
                        this.exitLandscapeFullscreen();
                      } else {
                        this.closeVideoOverlay();
                      }
                    })

                    Text(this.inAppVideoTitle)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    Row({ space: 6 }) {
                      this.PlayerPipIcon(20, '#FFFFFF')
                      Text('小窗')
                        .fontSize(13.5)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Color.White)
                    }
                    .height(40)
                    .padding({ left: 12, right: 12 })
                    .borderRadius(20)
                    .backgroundColor('#66000000')
                    .alignItems(VerticalAlign.Center)
                    .onClick(() => {
                      this.triggerPipOrMiniWindow();
                    })

                    Stack() {
                      this.PlayerMoreDotsIcon('#FFFFFF')
                    }
                    .width(48)
                    .height(48)
                    .borderRadius(24)
                    .backgroundColor('#66000000')
                    .onClick(() => {
                      this.showMoreSheet = !this.showMoreSheet;
                    })
                  }
                  .width('100%')
                  .padding({
                    left: Math.max(14, this.safeLeft + 10),
                    right: Math.max(14, this.safeRight + 10),
                    top: this.isPlayerFullscreen ? 12 : Math.max(14, this.safeTop + 8),
                    bottom: 16
                  })
                  .linearGradient({
                    angle: 180,
                    colors: [['#D9000000', 0.0], ['#00000000', 1.0]]
                  })

                  Blank()

                  // 底部双行渐变控制栏（Row 1: 进度条/直播状态；Row 2: 播放/网页版/线路/倍速/横竖屏/全屏）
                  Column({ space: 8 }) {
                    // 第一行：进度条或直播状态徽标
                    if (this.videoDuration > 0) {
                      Row({ space: 10 }) {
                        Text(formatVideoTime(this.videoCurrentTime))
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(Color.White)

                        Slider({
                          value: this.videoDuration > 0 ? this.videoCurrentTime : 1,
                          min: 0,
                          max: this.videoDuration > 0 ? this.videoDuration : 1,
                          step: 1
                        })
                          .layoutWeight(1)
                          .trackThickness(5)
                          .blockSize({ width: 18, height: 18 })
                          .selectedColor('#FF6699')
                          .trackColor('#59FFFFFF')
                          .blockColor(Color.White)
                          .onChange((value: number, mode: SliderChangeMode) => {
                            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
                              this.isSeeking = true;
                              this.videoCurrentTime = value;
                            } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
                              this.isSeeking = false;
                              this.videoCurrentTime = value;
                              try {
                                this.avPlayer?.seek(Math.floor(value * 1000), media.SeekMode.SEEK_PREV_SYNC);
                              } catch (seekErr) {
                                hilog.warn(DOMAIN, TAG, `AVPlayer seek failed: ${JSON.stringify(seekErr)}`);
                              }
                              this.scheduleHideOverlay();
                            }
                          })

                        Text(formatVideoTime(this.videoDuration))
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor('#D9FFFFFF')
                      }
                      .width('100%')
                    } else {
                      Row({ space: 8 }) {
                        Circle({ width: 8, height: 8 }).fill('#FF4D79')
                        Text('正在直播 LIVE')
                          .fontSize(13.5)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#FF6699')
                        Blank()
                      }
                      .width('100%')
                      .padding({ left: 4, bottom: 2 })
                    }

                    // 第二行：主控按钮栏
                    Row({ space: this.isCompactSmallWindow() ? 6 : 10 }) {
                      Stack() {
                        if (this.isVideoPlaying) {
                          this.PlayerVectorIcon(
                            'M6 4.5 L10 4.5 L10 19.5 L6 19.5 Z M14 4.5 L18 4.5 L18 19.5 L14 19.5 Z',
                            true,
                            26,
                            '#FFFFFF'
                          )
                        } else {
                          this.PlayerVectorIcon(
                            'M7 4.2 L20.2 12 L7 19.8 Z',
                            true,
                            26,
                            '#FFFFFF'
                          )
                        }
                      }
                      .width(this.isCompactSmallWindow() ? 40 : 46)
                      .height(this.isCompactSmallWindow() ? 40 : 46)
                      .borderRadius(this.isCompactSmallWindow() ? 20 : 23)
                      .backgroundColor('#59000000')
                      .onClick(() => {
                        this.togglePlayPause();
                      })

                      if (this.webFallbackTarget().length > 0) {
                        Row({ space: 4 }) {
                          Text('网页版')
                            .fontSize(13.5)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(Color.White)
                        }
                        .height(38)
                        .padding({ left: 12, right: 12 })
                        .borderRadius(19)
                        .backgroundColor('#4DFFFFFF')
                        .alignItems(VerticalAlign.Center)
                        .onClick(() => {
                          this.preConfigureWebCookies();
                          this.useWebFallback = true;
                          this.showMoreSheet = false;
                          this.controlsVisible = true;
                          this.releaseSystemPip();
                          this.releaseAvPlayer();
                        })
                      }

                      Blank()

                      if (this.videoStreams.length > 1) {
                        Row() {
                          Text(`线路 ${this.activeStreamIndex + 1}/${this.videoStreams.length}`)
                            .fontSize(13.5)
                            .fontWeight(FontWeight.Medium)
                            .fontColor(Color.White)
                        }
                        .height(38)
                        .padding({ left: 12, right: 12 })
                        .borderRadius(19)
                        .backgroundColor('#4DFFFFFF')
                        .alignItems(VerticalAlign.Center)
                        .onClick(() => {
                          this.showMoreSheet = true;
                        })
                      }

                      if (this.videoDuration > 0) {
                        Row() {
                          Text(this.videoSpeedLabel)
                            .fontSize(13.5)
                            .fontWeight(FontWeight.Bold)
                            .fontColor(Color.White)
                        }
                        .height(38)
                        .padding({ left: 13, right: 13 })
                        .borderRadius(19)
                        .backgroundColor('#4DFFFFFF')
                        .alignItems(VerticalAlign.Center)
                        .onClick(() => {
                          this.cycleVideoSpeed();
                        })
                      }

                      Row({ space: 5 }) {
                        this.PlayerVectorIcon(
                          'M4.9 8.7 C7.3 3.5 14.3 2.6 18.0 7.0 M18.2 3.4 L18.2 7.2 L14.4 7.0 M19.1 15.3 C16.7 20.5 9.7 21.4 6.0 17.0 M5.8 20.6 L5.8 16.8 L9.6 17.0',
                          false,
                          18,
                          '#FFFFFF'
                        )
                        Text(this.isPlayerFullscreen ? '竖屏' : '横屏')
                          .fontSize(13.5)
                          .fontWeight(FontWeight.Bold)
                          .fontColor(Color.White)
                      }
                      .height(40)
                      .padding({ left: 13, right: 13 })
                      .borderRadius(20)
                      .backgroundColor('#80FF6699')
                      .alignItems(VerticalAlign.Center)
                      .onClick(() => {
                        if (this.isPlayerFullscreen) {
                          this.exitLandscapeFullscreen();
                        } else {
                          this.enterLandscapeFullscreen();
                        }
                      })

                      Stack() {
                        if (this.isPlayerFullscreen) {
                          this.PlayerVectorIcon(
                            'M9 3.5 L9 9 L3.5 9 M15 3.5 L15 9 L20.5 9 M15 20.5 L15 15 L20.5 15 M9 20.5 L9 15 L3.5 15',
                            false,
                            24,
                            '#FFFFFF'
                          )
                        } else {
                          this.PlayerVectorIcon(
                            'M3.5 9 L3.5 3.5 L9 3.5 M15 3.5 L20.5 3.5 L20.5 9 M20.5 15 L20.5 20.5 L15 20.5 M9 20.5 L3.5 20.5 L3.5 15',
                            false,
                            24,
                            '#FFFFFF'
                          )
                        }
                      }
                      .width(this.isCompactSmallWindow() ? 40 : 46)
                      .height(this.isCompactSmallWindow() ? 40 : 46)
                      .borderRadius(this.isCompactSmallWindow() ? 20 : 23)
                      .backgroundColor('#59000000')
                      .onClick(() => {
                        if (this.isPlayerFullscreen) {
                          this.exitLandscapeFullscreen();
                        } else {
                          this.enterLandscapeFullscreen();
                        }
                      })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                  }
                  .width('100%')
                  .padding({
                    left: Math.max(14, this.safeLeft + 10),
                    right: Math.max(14, this.safeRight + 10),
                    top: 16,
                    bottom: this.isPlayerFullscreen ? Math.max(14, this.safeBottom + 8) : Math.max(16, this.safeBottom + 10)
                  })
                  .linearGradient({
                    angle: 0,
                    colors: [['#E6000000', 0.0], ['#00000000', 1.0]]
                  })
                }
                .width('100%')
                .height('100%')
                .hitTestBehavior(HitTestMode.Transparent)
              }

              if (this.showMoreSheet) {
                Column() {
                  this.VideoPlayerMoreSheet()
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Start)
                .alignItems(HorizontalAlign.End)
                .padding({
                  top: (this.isPlayerFullscreen ? 14 : Math.max(16, this.safeTop + 8)) + 56,
                  right: Math.max(14, this.safeRight + 10)
                })
                .backgroundColor('#4D000000')
                .onClick(() => {
                  this.showMoreSheet = false;
                  this.scheduleHideOverlay();
                })
              }
            }
          }
          .width(this.isSystemPipActive ? 1 : (this.isPlayerMiniWindow ? this.getMiniWindowWidth() : '100%'))
          .height(this.isSystemPipActive ? 1 : (this.isPlayerMiniWindow ? this.getMiniWindowHeight() : '100%'))
          .borderRadius(this.isPlayerMiniWindow && !this.isSystemPipActive ? 12 : 0)
          .clip(this.isPlayerMiniWindow && !this.isSystemPipActive)
          .opacity(this.isSystemPipActive ? 0.01 : 1)
          .backgroundColor(this.isSystemPipActive ? Color.Transparent : Color.Black)
          .border(this.isPlayerMiniWindow && !this.isSystemPipActive ? { width: 0.8, color: '#44FFFFFF' } : { width: 0 })
          .shadow(this.isPlayerMiniWindow && !this.isSystemPipActive ? { radius: 18, color: '#66000000', offsetX: 0, offsetY: 6 } : { radius: 0 })
          .margin(this.isPlayerMiniWindow && !this.isSystemPipActive ? { right: Math.max(12, this.safeRight + 8), bottom: this.safeBottom + 72 } : { right: 0, bottom: 0 })
          .translate(this.isPlayerMiniWindow && !this.isSystemPipActive ? { x: this.miniOffsetX, y: this.miniOffsetY } : { x: 0, y: 0 })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            if (this.isSystemPipActive) return;
            const w = Number(newArea.width);
            const h = Number(newArea.height);
            if (w > 0 && h > 0) {
              this.playerContainerW = w;
              this.playerContainerH = h;
              this.playerContainerAspect = w / h;
            }
          })
          .gesture(
            PanGesture()
              .onActionStart(() => {
                if (!this.isPlayerMiniWindow) return;
                this.dragStartX = this.miniOffsetX;
                this.dragStartY = this.miniOffsetY;
              })
              .onActionUpdate((event: GestureEvent) => {
                if (!this.isPlayerMiniWindow) return;
                this.miniOffsetX = this.dragStartX + event.offsetX;
                this.miniOffsetY = this.dragStartY + event.offsetY;
              })
          )
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(this.isSystemPipActive ? HitTestMode.None : (this.isPlayerMiniWindow ? HitTestMode.Transparent : HitTestMode.Default))
      }
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    if (this.inAppVideoVisible) {
      if (this.isSystemPipActive || this.isPlayerMiniWindow) {
        this.context.eventHub.emit(EVENT_BACK_PRESS);
        return true;
      }
      if (this.showMoreSheet) {
        this.showMoreSheet = false;
        this.scheduleHideOverlay();
      } else if (this.isPlayerFullscreen) {
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
