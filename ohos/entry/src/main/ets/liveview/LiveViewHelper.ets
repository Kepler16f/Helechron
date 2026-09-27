import { liveViewManager } from '@kit.LiveViewKit';
import { Want, WantAgent, wantAgent } from '@kit.AbilityKit';
import hilog from '@ohos.hilog';

const DOMAIN = 0x0000;
const TAG = 'HelechronLiveView';
const VIEW_ID = 60;
const BUNDLE_NAME = 'top.celechron.helechron';

/// Dart 侧推送的实况窗状态。
/// phase: 'ongoing' 上课中（target=下课时间）/ 'upcoming' 即将上课（target=开课时间）。
export interface LiveViewState {
  phase: string;
  title: string;
  subtitle: string;
  targetTimestamp: number;
}

/// 实况窗封装：上课中/临近开课时在状态栏胶囊、锁屏、通知中心展示原生倒计时。
///
/// 说明：
/// 1. Live View Kit 为受限开放能力，需在 AGC 为应用开通权益后才能实际弹出；
///    未开通或用户关闭实况窗开关时，所有调用静默失败，不影响应用其它功能。
/// 2. 计时由系统原生推进（timer + TIMER 胶囊），高频同步只在 phase/title/
///    目标时间变化时才产生一次 updateLiveView，普通上课期间几乎零更新。
/// 3. 应用被冻结/杀死后实况窗继续原生倒计时直到归零，下次应用唤醒时
///    由 5 秒同步纠正或结束。
export class LiveViewHelper {
  private static active: liveViewManager.LiveView | null = null;
  private static lastPhase = '';
  private static lastTitle = '';
  private static lastTarget = 0;
  private static sequence = 0;
  private static cachedWantAgent: WantAgent | null = null;

  static async sync(state: LiveViewState | null): Promise<void> {
    try {
      if (state === null) {
        await LiveViewHelper.stop();
        return;
      }
      const remaining = state.targetTimestamp - Date.now();
      if (remaining <= 0) {
        await LiveViewHelper.stop();
        return;
      }
      if (LiveViewHelper.active !== null &&
        state.phase === LiveViewHelper.lastPhase &&
        state.title === LiveViewHelper.lastTitle &&
        state.targetTimestamp === LiveViewHelper.lastTarget) {
        return;
      }
      if (!(await LiveViewHelper.isEnabled())) {
        return;
      }
      const view: liveViewManager.LiveView = {
        id: VIEW_ID,
        event: 'TIMER',
        sequence: ++LiveViewHelper.sequence,
        isMute: true,
        timer: {
          time: remaining,
          isCountdown: true,
          isPaused: false
        },
        liveViewData: {
          primary: {
            title: state.title,
            content: [{ text: state.subtitle }],
            keepTime: 15,
            clickAction: await LiveViewHelper.getClickAction()
          },
          capsule: {
            type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
            status: 1,
            icon: 'capsule_icon.png',
            backgroundColor: '#FF1E88E5',
            time: remaining,
            isCountdown: true,
            isPaused: false
          }
        }
      };
      if (LiveViewHelper.active === null) {
        await liveViewManager.startLiveView(view);
        hilog.info(DOMAIN, TAG,
          `startLiveView: ${state.phase}, ${state.title}, ${remaining}ms`);
      } else {
        await liveViewManager.updateLiveView(view);
        hilog.info(DOMAIN, TAG,
          `updateLiveView: ${state.phase}, ${state.title}, ${remaining}ms`);
      }
      LiveViewHelper.active = view;
      LiveViewHelper.lastPhase = state.phase;
      LiveViewHelper.lastTitle = state.title;
      LiveViewHelper.lastTarget = state.targetTimestamp;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `sync failed: ${JSON.stringify(e)}`);
      // 置空以便下个同步周期重新尝试 start（权益未开通等场景重试开销很小）
      LiveViewHelper.active = null;
    }
  }

  static async stop(): Promise<void> {
    const view = LiveViewHelper.active;
    LiveViewHelper.active = null;
    LiveViewHelper.lastPhase = '';
    LiveViewHelper.lastTitle = '';
    LiveViewHelper.lastTarget = 0;
    if (view === null) {
      return;
    }
    try {
      view.sequence = ++LiveViewHelper.sequence;
      await liveViewManager.stopLiveView(view);
      hilog.info(DOMAIN, TAG, 'stopLiveView');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `stop failed: ${JSON.stringify(e)}`);
    }
  }

  private static async isEnabled(): Promise<boolean> {
    try {
      return await liveViewManager.isLiveViewEnabled();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `isLiveViewEnabled failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  /// 点击实况窗回到应用首页。WantAgent 获取失败时退回普通 Want 拉起。
  private static async getClickAction(): Promise<Want | WantAgent> {
    if (LiveViewHelper.cachedWantAgent !== null) {
      return LiveViewHelper.cachedWantAgent;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: BUNDLE_NAME,
            abilityName: 'EntryAbility'
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITIES,
        requestCode: 0,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      LiveViewHelper.cachedWantAgent = await wantAgent.getWantAgent(info);
      return LiveViewHelper.cachedWantAgent;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `getWantAgent failed: ${JSON.stringify(e)}`);
      const want: Want = {
        bundleName: BUNDLE_NAME,
        abilityName: 'EntryAbility'
      };
      return want;
    }
  }
}
