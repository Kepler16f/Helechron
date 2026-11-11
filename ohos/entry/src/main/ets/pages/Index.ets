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
  private manualFullscreenLock: boolean = false;
  private sensorSubscribed: boolean = false;
  private currentOri: window.Orientation = window.Orientation.UNSPECIFIED;
  private lastSensorRotateMs: number = 0;
  private hideOverlayTimer: number = -1;
  private hudTimer: number = -1;
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

  private refreshAvoidAreas(win: window.Window): void {
    try {
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const sysArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutoutArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const b = Math.max(px2vp(navArea.bottomRect.height), px2vp(sysArea.bottomRect.height), px2vp(cutoutArea.bottomRect.height));
      const t = Math.max(px2vp(sysArea.topRect.height), px2vp(cutoutArea.topRect.height));
      const l = Math.max(px2vp(sysArea.leftRect.width), px2vp(cutoutArea.leftRect.width));
      const r = Math.max(px2vp(sysArea.rightRect.width), px2vp(cutoutArea.rightRect.width));
      this.safeBottom = b > 0 ? b : 24;
      this.safeTop = t > 0 ? t : 16;
      this.safeLeft = l;
      this.safeRight = r;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `refreshAvoidAreas failed: ${JSON.stringify(e)}`);
    }
  }

  private async loadSafeArea(): Promise<void> {
    try {
      const win = await window.getLastWindow(this.context);
      this.refreshAvoidAreas(win);
      this.apiLevel = resolveApiLevel();
      win.on('avoidAreaChange', () => {
        this.refreshAvoidAreas(win);
      });
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
      this.showMoreSheet = false;
      this.controlsVisible = true;
      this.miniOffsetX = 0;
      this.miniOffsetY = 0;
      this.xComponentSurfaceId = '';
      this.stopGravitySensor();
      this.clearOverlayTimers();
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
    this.applyPlayerWindowMode(window.Orientation.PORTRAIT, false);
    if (this.sensorRotation) {
      this.startGravitySensor();
    }
    if (!this.useWebFallback && this.xComponentSurfaceId.length > 0) {
      this.startAvPlayerPlayback(this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl);
    }
    this.scheduleHideOverlay();
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
    if (!this.inAppVideoVisible || !this.sensorRotation || this.isPlayerMiniWindow) {
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
      const win = await window.getLastWindow(this.context);
      await win.setPreferredOrientation(targetOri);
      if (this.inAppVideoVisible && hideBars && !this.isPlayerMiniWindow) {
        await win.setWindowSystemBarEnable([]);
      } else {
        await win.setWindowSystemBarEnable(['status', 'navigation']);
      }
      this.refreshAvoidAreas(win);
    } catch (e) {
      const be = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `applyPlayerWindowMode failed: ${be.code} ${be.message}`);
    }
  }

  private async releaseAvPlayer(): Promise<void> {
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
        if (state === PiPWindow.PiPState.STARTED) {
          this.isSystemPipActive = true;
          this.syncPipPlaybackState();
        } else if (state === PiPWindow.PiPState.ABOUT_TO_RESTORE) {
          this.isSystemPipActive = false;
          this.controlsVisible = true;
          this.scheduleHideOverlay();
        } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
          this.isSystemPipActive = false;
          this.pipController = undefined;
        }
      });
      ctrl.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) => {
        if (event === 'playbackStateChanged') {
          if (status === 1) {
            this.avPlayer?.play();
            this.isVideoPlaying = true;
          } else if (status === 0) {
            this.avPlayer?.pause();
            this.isVideoPlaying = false;
          } else {
            this.togglePlayPause();
          }
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
          await this.initOrUpdateSystemPip();
          if (this.pipController !== undefined) {
            this.manualFullscreenLock = false;
            this.isPlayerFullscreen = false;
            await this.applyPlayerWindowMode(window.Orientation.PORTRAIT, false);
            await this.pipController.startPiP();
            return;
          }
        }
      } catch (e) {
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
      player.on('videoSizeChange', (width: number, height: number) => {
        if (this.avPlayer !== player) return;
        if (width > 0 && height > 0) {
          this.videoContentWidth = width;
          this.videoContentHeight = height;
          this.videoAspectRatio = width / height;
        }
      });
      player.on('timeUpdate', (timeMs: number) => {
        if (this.avPlayer !== player || this.isSeeking) return;
        this.videoCurrentTime = Math.max(0, Math.floor(timeMs / 1000));
      });
      player.on('error', (err: BusinessError) => {
        if (this.avPlayer !== player) return;
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
            hilog.warn(DOMAIN, TAG, `AVPlayer prepare failed: ${JSON.stringify(prepErr)}`);
            this.switchNextStreamOrWeb();
          }
        } else if (state === 'prepared') {
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
          this.isVideoPlaying = true;
          this.videoLoading = false;
          this.pipController?.setAutoStartEnabled(true);
          this.syncPipPlaybackState();
          this.scheduleHideOverlay();
        } else if (state === 'paused') {
          this.isVideoPlaying = false;
          this.pipController?.setAutoStartEnabled(false);
          this.syncPipPlaybackState();
          if (!this.isSystemPipActive) {
            this.controlsVisible = true;
          }
        } else if (state === 'completed') {
          this.isVideoPlaying = false;
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
          'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36'
        };
        if (this.inAppVideoToken.length > 0) {
          headers['Cookie'] = `_token=${this.inAppVideoToken}; token=${this.inAppVideoToken}`;
          headers['Authorization'] = `Bearer ${this.inAppVideoToken}`;
        }
        const mediaSource: media.MediaSource = media.createMediaSourceWithUrl(targetUrl, headers);
        const strategy: media.PlaybackStrategy = { preferredBufferDuration: 10 };
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
    this.showMoreSheet = false;
    this.miniOffsetX = 0;
    this.miniOffsetY = 0;
    this.xComponentSurfaceId = '';
    this.stopGravitySensor();
    this.clearOverlayTimers();
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
    if (this.sensorRotation) {
      this.startGravitySensor();
    }
    this.scheduleHideOverlay();
  }

  private exitLandscapeFullscreen(): void {
    this.manualFullscreenLock = false;
    this.isPlayerFullscreen = false;
    this.showMoreSheet = false;
    this.applyPlayerWindowMode(window.Orientation.PORTRAIT, false);
    this.scheduleHideOverlay();
  }

  private enterMiniWindow(): void {
    this.manualFullscreenLock = false;
    this.isPlayerFullscreen = false;
    this.isPlayerMiniWindow = true;
    this.showMoreSheet = false;
    this.stopGravitySensor();
    this.clearOverlayTimers();
    this.applyPlayerWindowMode(window.Orientation.PORTRAIT, false);
  }

  private togglePlayPause(): void {
    if (this.useWebFallback || this.avPlayer === undefined) {
      return;
    }
    try {
      if (this.isVideoPlaying) {
        this.avPlayer.pause();
        this.isVideoPlaying = false;
      } else {
        this.avPlayer.play();
        this.isVideoPlaying = true;
        this.scheduleHideOverlay();
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
      this.startAvPlayerPlayback(this.activeVideoUrl);
      return;
    }
    if (this.webFallbackTarget().length > 0) {
      this.useWebFallback = true;
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

  private getXComponentWidth(): Length {
    if (this.playerContainerW > 0 && this.playerContainerH > 0 &&
        this.playerContainerAspect > this.videoAspectRatio) {
      return Math.round(this.playerContainerH * this.videoAspectRatio);
    }
    return '100%';
  }

  private getXComponentHeight(): Length {
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

  @Builder
  PlayerVectorIcon(commands: string, filled: boolean, size: number, colorStr: string) {
    Shape() {
      Path()
        .commands(commands)
        .fill(filled ? colorStr : '#00000000')
        .stroke(filled ? '#00000000' : colorStr)
        .strokeWidth(2.1)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    .width(size)
    .height(size)
    .viewPort({ x: 0, y: 0, width: 24, height: 24 })
  }

  @Builder
  PlayerMoreDotsIcon(colorStr: string) {
    Row({ space: 3 }) {
      Circle({ width: 4, height: 4 }).fill(colorStr)
      Circle({ width: 4, height: 4 }).fill(colorStr)
      Circle({ width: 4, height: 4 }).fill(colorStr)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  VideoPlayerMoreSheet() {
    Column({ space: 12 }) {
      if (!this.useWebFallback) {
        Text('播放倍速')
          .fontSize(12)
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
        Text('视频线路')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#B3FFFFFF')
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.videoStreams, (streamItem: StreamSource, idx: number) => {
            Text(streamItem.label)
              .fontSize(12)
              .fontColor(this.activeStreamIndex === idx ? '#FF6699' : Color.White)
              .fontWeight(this.activeStreamIndex === idx ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .borderRadius(8)
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
            .fontSize(12.5)
            .fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor('#330A84FF')
            .onClick(() => {
              this.useWebFallback = true;
              this.showMoreSheet = false;
              this.controlsVisible = true;
              this.releaseSystemPip();
              this.releaseAvPlayer();
            })
        } else if (this.useWebFallback && (this.videoStreams.length > 0 || isDirectStreamUrl(this.inAppVideoUrl))) {
          Text('返回原生流播放器')
            .fontSize(12.5)
            .fontColor(Color.White)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor('#33FF6699')
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

        if (this.useWebFallback) {
          Text('收起顶栏')
            .fontSize(12.5)
            .fontColor('#CCFFFFFF')
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(8)
            .backgroundColor('#26FFFFFF')
            .onClick(() => {
              this.showMoreSheet = false;
              this.controlsVisible = false;
            })
        }
      }
    }
    .width(300)
    .padding(14)
    .borderRadius(14)
    .backgroundColor('#E81A1A1E')
    .border({ width: 0.6, color: '#33FFFFFF' })
    .shadow({ radius: 20, color: '#88000000', offsetX: 0, offsetY: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SpeedPresetChip(label: string, spd: media.PlaybackSpeed) {
    Text(label)
      .fontSize(12)
      .fontColor(this.videoSpeedLabel === label ? '#FF6699' : Color.White)
      .fontWeight(this.videoSpeedLabel === label ? FontWeight.Bold : FontWeight.Normal)
      .padding({ left: 8, right: 8, top: 5, bottom: 5 })
      .borderRadius(8)
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
              }
              .width('100%')
              .height('100%')
              .padding({
                top: (!this.isPlayerMiniWindow && this.controlsVisible)
                  ? (this.isPlayerFullscreen ? 54 : (Math.max(14, this.safeTop + 6) + 46))
                  : 0
              })
            } else {
              XComponent({
                id: 'zhiyunPlayerXComponent',
                type: XComponentType.SURFACE,
                controller: this.xComponentController
              })
                .width(this.getXComponentWidth())
                .height(this.getXComponentHeight())
                .aspectRatio(this.videoAspectRatio)
                .onLoad(() => {
                  this.xComponentSurfaceId = this.xComponentController.getXComponentSurfaceId();
                  const target = this.activeVideoUrl.length > 0 ? this.activeVideoUrl : this.inAppVideoUrl;
                  this.startAvPlayerPlayback(target);
                })
                .onClick(() => {
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
            }

            // 应用内悬浮小窗仅展示右上角 2 个简洁图标钮
            if (this.isPlayerMiniWindow) {
              Column() {
                Row({ space: 6 }) {
                  Stack() {
                    this.PlayerVectorIcon('M4 9 L4 4 L9 4 M15 4 L20 4 L20 9 M20 15 L20 20 L15 20 M9 20 L4 20 L4 15', false, 14, '#FFFFFF')
                  }
                  .width(26)
                  .height(26)
                  .borderRadius(13)
                  .backgroundColor('#99000000')
                  .onClick(() => {
                    this.isPlayerMiniWindow = false;
                    this.enterLandscapeFullscreen();
                  })

                  Stack() {
                    this.PlayerVectorIcon('M6 6 L18 18 M18 6 L6 18', false, 14, '#FFFFFF')
                  }
                  .width(26)
                  .height(26)
                  .borderRadius(13)
                  .backgroundColor('#99000000')
                  .onClick(() => {
                    this.closeVideoOverlay();
                  })
                }
              }
              .width('100%')
              .height('100%')
              .padding({ top: 6, right: 6 })
              .alignItems(HorizontalAlign.End)
              .justifyContent(FlexAlign.Start)
              .hitTestBehavior(HitTestMode.Transparent)
            }

            // 中央加载/播放提示与 HUD（非应用内小窗且非系统画中画时展示）
            if (!this.isPlayerMiniWindow && !this.isSystemPipActive) {
              if (!this.useWebFallback && this.videoLoading) {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color('#FF6699')
              }

              if (!this.useWebFallback && this.controlsVisible && !this.videoLoading) {
                Stack() {
                  this.PlayerVectorIcon(
                    this.isVideoPlaying
                      ? 'M6.5 5 L10.2 5 L10.2 19 L6.5 19 Z M13.8 5 L17.5 5 L17.5 19 L13.8 19 Z'
                      : 'M7 4.5 L19.5 12 L7 19.5 Z',
                    true,
                    26,
                    '#FFFFFF'
                  )
                }
                .width(56)
                .height(56)
                .borderRadius(28)
                .backgroundColor('#80000000')
                .onClick(() => {
                  this.togglePlayPause();
                })
              }

              if (this.hudText.length > 0) {
                Column() {
                  Text(this.hudText)
                    .fontSize(13)
                    .fontColor(Color.White)
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                    .borderRadius(18)
                    .backgroundColor('#CC1C1C1E')
                }
                .width('100%')
                .height('100%')
                .padding({ top: (this.isPlayerFullscreen ? 14 : this.safeTop + 12) + 52 })
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Start)
                .hitTestBehavior(HitTestMode.None)
              }

              // 网页全屏/收起顶栏时的右上角微弱呼出钮
              if (this.useWebFallback && !this.controlsVisible) {
                Row() {
                  Blank()
                  Stack() {
                    this.PlayerMoreDotsIcon('#FFFFFF')
                  }
                  .width(34)
                  .height(34)
                  .borderRadius(17)
                  .backgroundColor('#88000000')
                  .onClick(() => {
                    this.controlsVisible = true;
                  })
                }
                .width('100%')
                .padding({
                  top: this.isPlayerFullscreen ? 12 : Math.max(14, this.safeTop + 6),
                  right: Math.max(12, this.safeRight + 8)
                })
                .position({ x: 0, y: 0 })
                .hitTestBehavior(HitTestMode.Transparent)
              }

              // 悬浮渐隐工具栏（顶部 + 底部）
              if (this.controlsVisible) {
                Column() {
                  // 顶部渐变控制栏
                  Row({ space: 6 }) {
                    Stack() {
                      this.PlayerVectorIcon('M15 5 L8 12 L15 19', false, 20, '#FFFFFF')
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .onClick(() => {
                      if (this.isPlayerFullscreen) {
                        this.exitLandscapeFullscreen();
                      } else {
                        this.closeVideoOverlay();
                      }
                    })

                    Text(this.inAppVideoTitle)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)

                    Stack() {
                      this.PlayerVectorIcon(
                        'M6.5 4.5 L17.5 4.5 L17.5 19.5 L6.5 19.5 Z M3.5 9.5 L3.5 6 L6.8 6 M20.5 14.5 L20.5 18 L17.2 18',
                        false,
                        19,
                        this.sensorRotation ? '#FF6699' : '#FFFFFF'
                      )
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .onClick(() => {
                      this.sensorRotation = !this.sensorRotation;
                      if (this.sensorRotation) {
                        this.startGravitySensor();
                        this.showHudMessage('已开启重力旋屏');
                      } else {
                        this.stopGravitySensor();
                        this.showHudMessage('已锁定方向');
                      }
                      this.scheduleHideOverlay();
                    })

                    Stack() {
                      this.PlayerVectorIcon(
                        'M3 5 L21 5 L21 19 L3 19 Z M12 12 L18.5 12 L18.5 16.5 L12 16.5 Z',
                        false,
                        19,
                        '#FFFFFF'
                      )
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .onClick(() => {
                      this.triggerPipOrMiniWindow();
                    })

                    Stack() {
                      this.PlayerMoreDotsIcon('#FFFFFF')
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(18)
                    .onClick(() => {
                      this.showMoreSheet = !this.showMoreSheet;
                    })
                  }
                  .width('100%')
                  .padding({
                    left: Math.max(12, this.safeLeft + 8),
                    right: Math.max(12, this.safeRight + 8),
                    top: this.isPlayerFullscreen ? 12 : Math.max(14, this.safeTop + 6),
                    bottom: 14
                  })
                  .linearGradient({
                    angle: 180,
                    colors: [['#CC000000', 0.0], ['#00000000', 1.0]]
                  })

                  Blank()

                  // 底部渐变进度控制栏（原生 AVPlayer 模式）
                  if (!this.useWebFallback) {
                    Row({ space: 8 }) {
                      Stack() {
                        this.PlayerVectorIcon(
                          this.isVideoPlaying
                            ? 'M6.5 5 L10.2 5 L10.2 19 L6.5 19 Z M13.8 5 L17.5 5 L17.5 19 L13.8 19 Z'
                            : 'M7 4.5 L19.5 12 L7 19.5 Z',
                          true,
                          18,
                          '#FFFFFF'
                        )
                      }
                      .width(34)
                      .height(34)
                      .borderRadius(17)
                      .onClick(() => {
                        this.togglePlayPause();
                      })

                      Text(formatVideoTime(this.videoCurrentTime))
                        .fontSize(11.5)
                        .fontColor(Color.White)

                      Slider({
                        value: this.videoDuration > 0 ? this.videoCurrentTime : 1,
                        min: 0,
                        max: this.videoDuration > 0 ? this.videoDuration : 1,
                        step: 1
                      })
                        .layoutWeight(1)
                        .selectedColor('#FF6699')
                        .trackColor('#4DFFFFFF')
                        .blockColor(Color.White)
                        .enabled(this.videoDuration > 0)
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

                      Text(this.videoDuration > 0 ? formatVideoTime(this.videoDuration) : 'LIVE')
                        .fontSize(11.5)
                        .fontColor(this.videoDuration > 0 ? '#CCFFFFFF' : '#FF6699')
                        .fontWeight(this.videoDuration > 0 ? FontWeight.Normal : FontWeight.Bold)

                      Text(this.videoSpeedLabel)
                        .fontSize(11.5)
                        .fontColor(Color.White)
                        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                        .borderRadius(11)
                        .backgroundColor('#44FFFFFF')
                        .onClick(() => {
                          this.cycleVideoSpeed();
                        })

                      Stack() {
                        this.PlayerVectorIcon(
                          this.isPlayerFullscreen
                            ? 'M9 4 L9 9 L4 9 M15 4 L15 9 L20 9 M15 20 L15 15 L20 15 M9 20 L9 15 L4 15'
                            : 'M4 9 L4 4 L9 4 M15 4 L20 4 L20 9 M20 15 L20 20 L15 20 M9 20 L4 20 L4 15',
                          false,
                          18,
                          '#FFFFFF'
                        )
                      }
                      .width(34)
                      .height(34)
                      .borderRadius(17)
                      .onClick(() => {
                        if (this.isPlayerFullscreen) {
                          this.exitLandscapeFullscreen();
                        } else {
                          this.enterLandscapeFullscreen();
                        }
                      })
                    }
                    .width('100%')
                    .padding({
                      left: Math.max(12, this.safeLeft + 8),
                      right: Math.max(12, this.safeRight + 8),
                      top: 14,
                      bottom: this.isPlayerFullscreen ? Math.max(12, this.safeBottom + 6) : Math.max(14, this.safeBottom + 8)
                    })
                    .linearGradient({
                      angle: 0,
                      colors: [['#CC000000', 0.0], ['#00000000', 1.0]]
                    })
                  }
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
                  top: (this.isPlayerFullscreen ? 12 : Math.max(14, this.safeTop + 6)) + 46,
                  right: Math.max(12, this.safeRight + 8)
                })
                .backgroundColor('#33000000')
                .onClick(() => {
                  this.showMoreSheet = false;
                  this.scheduleHideOverlay();
                })
              }
            }
          }
          .width(this.isPlayerMiniWindow ? 256 : '100%')
          .height(this.isPlayerMiniWindow ? 144 : '100%')
          .borderRadius(this.isPlayerMiniWindow ? 12 : 0)
          .clip(this.isPlayerMiniWindow)
          .backgroundColor(Color.Black)
          .border(this.isPlayerMiniWindow ? { width: 0.8, color: '#44FFFFFF' } : { width: 0 })
          .shadow(this.isPlayerMiniWindow ? { radius: 18, color: '#66000000', offsetX: 0, offsetY: 6 } : { radius: 0 })
          .margin(this.isPlayerMiniWindow ? { right: Math.max(12, this.safeRight + 8), bottom: this.safeBottom + 72 } : { right: 0, bottom: 0 })
          .translate(this.isPlayerMiniWindow ? { x: this.miniOffsetX, y: this.miniOffsetY } : { x: 0, y: 0 })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
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
        .hitTestBehavior(this.isPlayerMiniWindow ? HitTestMode.Transparent : HitTestMode.Default)
      }
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    if (this.inAppVideoVisible) {
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
