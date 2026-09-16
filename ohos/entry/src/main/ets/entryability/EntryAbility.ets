import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import notificationManager from '@ohos.notificationManager';
import { calendarManager } from '@kit.CalendarKit';
import { BusinessError } from '@kit.BasicServicesKit';
import reminderAgentManager from '@ohos.reminderAgentManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import hilog from '@ohos.hilog';
import preferences from '@ohos.data.preferences';

const DOMAIN = 0x0000;
const TAG = 'HelechronNative';
const CHANNEL_NAME = 'top.celechron.helechron/native';
const PERMISSION_READ_CALENDAR = 'ohos.permission.READ_CALENDAR';
const PERMISSION_WRITE_CALENDAR = 'ohos.permission.WRITE_CALENDAR';
const DEFAULT_REMINDER_MINUTES = 15;
const MAX_AGENT_REMINDERS = 30;
const ALARM_HORIZON_MS = 7 * 24 * 60 * 60 * 1000;

interface CalendarEventPayload {
  uid: string;
  summary: string;
  description: string;
  location: string;
  startTime: number;
  endTime: number;
}

interface AddEventResult {
  added: number;
  firstError: string;
}

export default class EntryAbility extends FlutterAbility {
  private methodChannel: MethodChannel | null = null;
  private samplePayload: CalendarEventPayload | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);

    this.methodChannel = new MethodChannel(
      flutterEngine.getDartExecutor().getBinaryMessenger(),
      CHANNEL_NAME
    );

    this.methodChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handleMethodCall(call, result);
      }
    });
  }

  private handleMethodCall(call: MethodCall, result: MethodResult): void {
    hilog.info(DOMAIN, TAG, `Received method call: ${call.method}`);
    switch (call.method) {
      case 'requestNotificationPermission':
        this.requestNotificationPermission(result);
        break;
      case 'showNotification':
        this.showNotification(call, result);
        break;
      case 'cancelNotification':
        this.cancelNotification(call, result);
        break;
      case 'cancelAllNotifications':
        this.cancelAllNotifications(result);
        break;
      case 'isNotificationEnabled':
        this.isNotificationEnabled(result);
        break;
      case 'checkCalendarPermission':
        this.checkCalendarPermission(result);
        break;
      case 'requestCalendarPermission':
        this.requestCalendarPermission(result);
        break;
      case 'syncCalendarEvents':
        this.syncCalendarEvents(call, result);
        break;
      case 'clearCalendarEvents':
        this.clearCalendarEvents(result);
        break;
      case 'hasSyncedCalendar':
        this.hasSyncedCalendar(result);
        break;
      case 'calendarDiagnostics':
        this.calendarDiagnostics(result);
        break;
      case 'calendarSelfTest':
        this.calendarSelfTest(result);
        break;
      case 'setWidgetData':
        this.setWidgetData(call, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  // ==================== Calendar ====================

  private getTokenId(): number {
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
    );
    return bundleInfo.appInfo.accessTokenId;
  }

  private checkCalendarPermission(result: MethodResult): void {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId = this.getTokenId();
      const readStatus = atManager.checkAccessTokenSync(tokenId, PERMISSION_READ_CALENDAR);
      const writeStatus = atManager.checkAccessTokenSync(tokenId, PERMISSION_WRITE_CALENDAR);
      const granted =
        readStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED &&
        writeStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      hilog.info(DOMAIN, TAG, `checkCalendarPermission: read=${readStatus}, write=${writeStatus}, granted=${granted}`);
      result.success(granted);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `checkCalendarPermission failed: ${JSON.stringify(err)}`);
      result.success(false);
    }
  }

  private requestCalendarPermission(result: MethodResult): void {
    this.doRequestCalendarPermission(result);
  }

  private async doRequestCalendarPermission(result: MethodResult): Promise<void> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const permissions: Array<Permissions> = [
        PERMISSION_READ_CALENDAR,
        PERMISSION_WRITE_CALENDAR,
      ];
      const requestResult = await atManager.requestPermissionsFromUser(this.context, permissions);
      let allGranted = true;
      for (let i = 0; i < requestResult.authResults.length; i++) {
        if (requestResult.authResults[i] !== 0) {
          allGranted = false;
          break;
        }
      }
      hilog.info(DOMAIN, TAG, `requestCalendarPermission: authResults=${JSON.stringify(requestResult.authResults)}, allGranted=${allGranted}`);

      const readStatus = atManager.checkAccessTokenSync(this.getTokenId(), PERMISSION_READ_CALENDAR);
      const writeStatus = atManager.checkAccessTokenSync(this.getTokenId(), PERMISSION_WRITE_CALENDAR);
      hilog.info(DOMAIN, TAG, `requestCalendarPermission: afterRequest read=${readStatus}, write=${writeStatus}`);
      result.success(allGranted);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `requestCalendarPermission failed: ${JSON.stringify(err)}`);
      result.success(false);
    }
  }

  private getCalendarManagerInstance(): calendarManager.CalendarManager {
    return calendarManager.getCalendarManager(this.context);
  }

  private async getTargetCalendar(): Promise<calendarManager.Calendar> {
    const manager = this.getCalendarManagerInstance();
    // 仅写入系统默认日历，确保系统日历 App 一定可见（不创建第三方 LOCAL 账户）
    return await manager.getCalendar();
  }

  private async hasSyncedCalendar(result: MethodResult): Promise<void> {
    try {
      const calendar = await this.getTargetCalendar();
      let found = false;
      try {
        const events = await calendar.getEvents();
        for (let i = 0; i < events.length; i++) {
          const title = events[i].title || '';
          if (title.indexOf('[') === 0) {
            found = true;
            break;
          }
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `hasSyncedCalendar getEvents error: ${JSON.stringify(e)}`);
      }
      hilog.info(DOMAIN, TAG, `hasSyncedCalendar: ${found}`);
      result.success(found);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `hasSyncedCalendar failed: ${JSON.stringify(err)}`);
      result.success(false);
    }
  }

  private async calendarDiagnostics(result: MethodResult): Promise<void> {
    try {
      const calendar = await this.getTargetCalendar();
      const account = calendar.getAccount();
      const events = await calendar.getEvents();
      let ours = 0;
      let sample = '';
      for (let i = 0; i < events.length; i++) {
        const t = events[i].title || '';
        if (t.indexOf('[') === 0) {
          ours++;
          if (sample === '') {
            const d = new Date(events[i].startTime);
            sample = `${t} @ ${d.toISOString()}`;
          }
        }
      }
      const msg = `calendarId=${calendar.id}, account=${account.name}/${account.type}, totalEvents=${events.length}, ourEvents=${ours}, sample=${sample}`;
      hilog.info(DOMAIN, TAG, `calendarDiagnostics: ${msg}`);
      result.success(msg);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `calendarDiagnostics failed: ${JSON.stringify(err)}`);
      result.success(`diagnostics failed: ${JSON.stringify(err)}`);
    }
  }

  private formatError(e: Object): string {
    try {
      const be = e as BusinessError;
      return `code=${be.code},msg=${be.message}`;
    } catch (ignore) {
      return JSON.stringify(e);
    }
  }

  // Flutter-ohos decodes channel maps as Map<string, Object>, not plain objects,
  // so fields must be read with .get() (property access returns undefined).
  private str(m: Map<string, Object>, key: string): string {
    const v = m.get(key);
    if (typeof v === 'string') {
      return v;
    }
    return '';
  }

  private num(m: Map<string, Object>, key: string): number {
    const v = m.get(key);
    if (typeof v === 'number') {
      return v;
    }
    return 0;
  }

  private async calendarSelfTest(result: MethodResult): Promise<void> {
    const steps: string[] = [];
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const tokenId = this.getTokenId();
      const readStatus = atManager.checkAccessTokenSync(tokenId, PERMISSION_READ_CALENDAR);
      const writeStatus = atManager.checkAccessTokenSync(tokenId, PERMISSION_WRITE_CALENDAR);
      steps.push(`perm(r=${readStatus},w=${writeStatus})`);

      const manager = this.getCalendarManagerInstance();
      const calendar = await manager.getCalendar();
      const account = calendar.getAccount();
      steps.push(`cal=${calendar.id}/${account.name}/${account.type}`);

      // Incremental field tests: each variant adds one more field,
      // so the first FAIL pinpoints the offending field.
      const now = Date.now() + 120000;
      const v0: calendarManager.Event = {
        title: 't0', type: calendarManager.EventType.NORMAL, startTime: now, endTime: now + 3600000
      };
      const v1: calendarManager.Event = {
        title: 't1', type: calendarManager.EventType.NORMAL, startTime: now + 1, endTime: now + 3600001, isAllDay: false
      };
      const v2: calendarManager.Event = {
        title: 't2', type: calendarManager.EventType.NORMAL, startTime: now + 2, endTime: now + 3600002, isAllDay: false, reminderTime: [15]
      };
      const v3: calendarManager.Event = {
        title: 't3', type: calendarManager.EventType.NORMAL, startTime: now + 3, endTime: now + 3600003, isAllDay: false, reminderTime: [15], location: { location: 'test-place' }
      };
      const v4: calendarManager.Event = {
        title: 't4', type: calendarManager.EventType.NORMAL, startTime: now + 4, endTime: now + 3600004, isAllDay: false, reminderTime: [15], description: 'test-desc'
      };
      const variants: calendarManager.Event[] = [v0, v1, v2, v3, v4];

      // v5: real data from the first sync payload (Chinese title/desc/location)
      const s = this.samplePayload;
      if (s !== null && s !== undefined) {
        steps.push(`sample:sumLen=${s.summary.length},descLen=${s.description.length},locLen=${s.location.length}`);
        const v5: calendarManager.Event = {
          title: s.summary,
          type: calendarManager.EventType.NORMAL,
          startTime: now + 5,
          endTime: now + 3600005,
          isAllDay: false,
          reminderTime: [15],
          description: s.description
        };
        if (s.location !== null && s.location !== undefined && s.location !== '') {
          v5.location = { location: s.location };
        }
        variants.push(v5);
      }

      // v6: alarm mode uses an empty reminderTime array
      const v6: calendarManager.Event = {
        title: 't6', type: calendarManager.EventType.NORMAL, startTime: now + 6, endTime: now + 3600006, isAllDay: false, reminderTime: []
      };
      variants.push(v6);
      for (let i = 0; i < variants.length; i++) {
        try {
          const id = await calendar.addEvent(variants[i]);
          steps.push(`v${i}=OK(${id})`);
          if (id > 0) {
            try { await calendar.deleteEvents([id]); } catch (delErr) { steps.push(`v${i}del=F(${this.formatError(delErr)})`); }
          }
        } catch (e) {
          steps.push(`v${i}=FAIL(${this.formatError(e)})`);
        }
      }

      const msg = steps.join(' | ');
      hilog.info(DOMAIN, TAG, `calendarSelfTest: ${msg}`);
      result.success(msg);
    } catch (err) {
      const msg = steps.join(' | ') + ` | FATAL: ${this.formatError(err)}`;
      hilog.error(DOMAIN, TAG, `calendarSelfTest: ${msg}`);
      result.success(msg);
    }
  }

  private async enableReminders(calendar: calendarManager.Calendar): Promise<void> {
    try {
      const config: calendarManager.CalendarConfig = { enableReminder: true };
      await calendar.setConfig(config);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `enableReminders setConfig failed: ${JSON.stringify(err)}`);
    }
  }

  private async deleteOwnedEvents(calendar: calendarManager.Calendar): Promise<number> {
    let deleted = 0;
    try {
      const events = await calendar.getEvents();
      const ids: number[] = [];
      for (let i = 0; i < events.length; i++) {
        const id = events[i].id;
        const title = events[i].title || '';
        if (id !== undefined && id !== null && title.indexOf('[') === 0) {
          ids.push(id);
        }
      }
      if (ids.length > 0) {
        await calendar.deleteEvents(ids);
        deleted = ids.length;
      }
      hilog.info(DOMAIN, TAG, `deleteOwnedEvents: deleted ${deleted} previously synced events`);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `deleteOwnedEvents failed: ${JSON.stringify(err)}`);
    }
    return deleted;
  }

  private async addEventConcurrent(
    calendar: calendarManager.Calendar,
    events: calendarManager.Event[]
  ): Promise<AddEventResult> {
    let added = 0;
    let failed = 0;
    let firstError = '';
    // Serial write: the calendar service rejects overlapping addEvent calls
    // (self-test proved a single serial addEvent succeeds with the same fields).
    const chunkSize = 1;
    for (let start = 0; start < events.length; start += chunkSize) {
      const end = Math.min(start + chunkSize, events.length);
      const tasks: Promise<void>[] = [];
      for (let i = start; i < end; i++) {
        const ev = events[i];
        const task = calendar.addEvent(ev)
          .then((id: number): void => {
            if (id > 0) {
              added++;
            } else {
              failed++;
              if (firstError === '') {
                firstError = `addEvent returned id=${id}`;
              }
              hilog.error(DOMAIN, TAG, `addEvent: invalid id=${id} for title=${ev.title}`);
            }
          })
          .catch((e: Object): void => {
            failed++;
            const errStr = this.formatError(e);
            if (firstError === '') {
              firstError = errStr;
            }
            hilog.error(DOMAIN, TAG, `addEvent failed: ${errStr}`);
          });
        tasks.push(task);
      }
      await Promise.all(tasks);
    }
    hilog.info(DOMAIN, TAG, `addEventConcurrent: added=${added}, failed=${failed}, firstError=${firstError}`);
    const res: AddEventResult = { added: added, firstError: firstError };
    return res;
  }

  private async updateAlarmReminders(
    payloads: CalendarEventPayload[],
    reminderMinutes: number
  ): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
    } catch (cancelErr) {
      hilog.warn(DOMAIN, TAG, `cancelAllReminders failed: ${JSON.stringify(cancelErr)}`);
    }
    const now = Date.now();
    let published = 0;
    for (let i = 0; i < payloads.length && published < MAX_AGENT_REMINDERS; i++) {
      const payload = payloads[i];
      if (payload.startTime <= 0) {
        continue;
      }
      const triggerMs = payload.startTime - reminderMinutes * 60 * 1000;
      if (triggerMs <= now) {
        continue;
      }
      if (triggerMs - now > ALARM_HORIZON_MS) {
        continue;
      }
      const trigger = new Date(triggerMs);
      const reminder: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: {
          year: trigger.getFullYear(),
          month: trigger.getMonth() + 1,
          day: trigger.getDate(),
          hour: trigger.getHours(),
          minute: trigger.getMinutes(),
          second: 0
        },
        title: payload.summary,
        content: payload.description,
        notificationId: published,
        ringDuration: 5,
        snoozeTimes: 0
      };
      try {
        await reminderAgentManager.publishReminder(reminder);
        published++;
      } catch (pubErr) {
        hilog.error(DOMAIN, TAG, `publishReminder failed: ${JSON.stringify(pubErr)}`);
      }
    }
    hilog.info(DOMAIN, TAG, `updateAlarmReminders: published ${published} alarm reminders`);
  }

  private syncCalendarEvents(call: MethodCall, result: MethodResult): void {
    const rawList = call.argument('events') as Map<string, Object>[];
    if (rawList === null || rawList === undefined || rawList.length === 0) {
      hilog.info(DOMAIN, TAG, 'syncCalendarEvents: no events to sync');
      result.success(0);
      return;
    }
    // Convert decoded Map<string, Object> entries into typed payloads.
    const payloads: CalendarEventPayload[] = [];
    for (let i = 0; i < rawList.length; i++) {
      const m = rawList[i];
      const payload: CalendarEventPayload = {
        uid: this.str(m, 'uid'),
        summary: this.str(m, 'summary'),
        description: this.str(m, 'description'),
        location: this.str(m, 'location'),
        startTime: this.num(m, 'startTime'),
        endTime: this.num(m, 'endTime')
      };
      payloads.push(payload);
    }
    hilog.info(DOMAIN, TAG, `syncCalendarEvents: decoded ${payloads.length} payloads, firstTitle=${payloads[0].summary}`);
    const reminderMinutesRaw = call.argument('reminderMinutes') as number;
    const reminderMinutes =
      (reminderMinutesRaw !== null && reminderMinutesRaw !== undefined && reminderMinutesRaw > 0)
        ? reminderMinutesRaw
        : DEFAULT_REMINDER_MINUTES;
    const useAlarm = call.argument('useAlarm') === true;
    hilog.info(DOMAIN, TAG, `syncCalendarEvents: ${payloads.length} events, reminder=${reminderMinutes}min, useAlarm=${useAlarm}`);
    this.doCalendarSync(payloads, reminderMinutes, useAlarm, result);
  }

  private async doCalendarSync(
    payloads: CalendarEventPayload[],
    reminderMinutes: number,
    useAlarm: boolean,
    result: MethodResult
  ): Promise<void> {
    try {
      this.samplePayload = payloads[0];
      const calendar = await this.getTargetCalendar();
      await this.enableReminders(calendar);

      // 清理上次本应用写入的日程（按标题前缀 "[" 识别，仅删自己的）
      const cleaned = await this.deleteOwnedEvents(calendar);

      const events: calendarManager.Event[] = [];
      let skipped = 0;
      for (let i = 0; i < payloads.length; i++) {
        const payload = payloads[i];
        if (payload.startTime <= 0 || payload.endTime <= 0 || payload.endTime <= payload.startTime) {
          skipped++;
          continue;
        }
        const event: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: payload.summary,
          startTime: payload.startTime,
          endTime: payload.endTime,
          isAllDay: false,
          reminderTime: useAlarm ? [] : [reminderMinutes]
        };
        if (payload.location !== null && payload.location !== undefined && payload.location !== '') {
          event.location = { location: payload.location };
        }
        if (payload.description !== null && payload.description !== undefined && payload.description !== '') {
          event.description = payload.description;
        }
        events.push(event);
      }
      hilog.info(DOMAIN, TAG, `doCalendarSync: ${events.length} valid events, ${skipped} skipped, cleaned=${cleaned}`);
      const addResult = await this.addEventConcurrent(calendar, events);
      const added = addResult.added;

      // 回读校验：统计默认日历中本应用写入的日程数量
      let verified = 0;
      try {
        const after = await calendar.getEvents();
        for (let i = 0; i < after.length; i++) {
          const t = after[i].title || '';
          if (t.indexOf('[') === 0) {
            verified++;
          }
        }
      } catch (verifyErr) {
        hilog.warn(DOMAIN, TAG, `verify getEvents failed: ${JSON.stringify(verifyErr)}`);
      }
      hilog.info(DOMAIN, TAG, `doCalendarSync: added=${added}, verifiedInCalendar=${verified}`);

      if (useAlarm) {
        await this.updateAlarmReminders(payloads, reminderMinutes);
      }

      if (added === 0 && events.length > 0) {
        const detail = `added=0, verified=${verified}, firstError=${addResult.firstError}, validEvents=${events.length}, skipped=${skipped}`;
        result.error('CALENDAR_SYNC_FAILED', detail, null);
        return;
      }
      result.success(verified > 0 ? verified : added);
    } catch (err) {
      const detail = JSON.stringify(err);
      hilog.error(DOMAIN, TAG, `doCalendarSync failed: ${detail}`);
      result.error('CALENDAR_SYNC_FAILED', detail, null);
    }
  }

  private clearCalendarEvents(result: MethodResult): void {
    this.doClearCalendarEvents(result);
  }

  private async doClearCalendarEvents(result: MethodResult): Promise<void> {
    try {
      const calendar = await this.getTargetCalendar();
      // 仅删除本应用写入的日程，绝不动用户的日历账户
      const deleted = await this.deleteOwnedEvents(calendar);

      try {
        await reminderAgentManager.cancelAllReminders();
      } catch (cancelErr) {
        hilog.warn(DOMAIN, TAG, `cancelAllReminders failed: ${JSON.stringify(cancelErr)}`);
      }

      hilog.info(DOMAIN, TAG, `doClearCalendarEvents completed, deleted ${deleted} events`);
      result.success(deleted);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `doClearCalendarEvents failed: ${JSON.stringify(err)}`);
      result.success(0);
    }
  }

  // ==================== Notifications ====================

  private requestNotificationPermission(result: MethodResult): void {
    notificationManager.requestEnableNotification(this.context)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Notification permission granted or requested');
        result.success(true);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, `requestEnableNotification failed: ${JSON.stringify(err)}`);
        result.success(false);
      });
  }

  private isNotificationEnabled(result: MethodResult): void {
    notificationManager.isNotificationEnabled()
      .then((enabled: boolean) => {
        result.success(enabled);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, `isNotificationEnabled failed: ${JSON.stringify(err)}`);
        result.success(false);
      });
  }

  private showNotification(call: MethodCall, result: MethodResult): void {
    const id: number = call.argument('id') ?? 0;
    const title: string = call.argument('title') ?? '';
    const text: string = call.argument('text') ?? '';
    const additionalText: string = call.argument('additionalText') ?? '';

    const notificationRequest: notificationManager.NotificationRequest = {
      id: id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
          additionalText: additionalText
        }
      }
    };

    notificationManager.publish(notificationRequest)
      .then(() => {
        hilog.info(DOMAIN, TAG, `Notification published successfully, id: ${id}`);
        result.success(true);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, `Failed to publish notification: ${JSON.stringify(err)}`);
        result.success(false);
      });
  }

  private cancelNotification(call: MethodCall, result: MethodResult): void {
    const id: number = call.argument('id') ?? 0;
    notificationManager.cancel(id)
      .then(() => {
        result.success(true);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, `Failed to cancel notification: ${JSON.stringify(err)}`);
        result.success(false);
      });
  }

  private cancelAllNotifications(result: MethodResult): void {
    notificationManager.cancelAll()
      .then(() => {
        result.success(true);
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, `Failed to cancel all notifications: ${JSON.stringify(err)}`);
        result.success(false);
      });
  }

  // ==================== Widget ====================

  private widgetPrefsName = 'helechron_widget_data';
  private widgetPrefs: preferences.Preferences | null = null;

  private async getWidgetPrefs(): Promise<preferences.Preferences> {
    if (this.widgetPrefs === null) {
      this.widgetPrefs = await preferences.getPreferences(
        getContext(this),
        this.widgetPrefsName
      );
    }
    return this.widgetPrefs;
  }

  private async setWidgetData(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const key = call.argument('key') as string;
      const value = call.argument('value') as string;
      if (key === null || key === undefined || key === '') {
        result.success(false);
        return;
      }
      const prefs = await this.getWidgetPrefs();
      await prefs.put(key, value);
      await prefs.flush();
      hilog.info(DOMAIN, TAG, `setWidgetData: key=${key}, value=${(value !== null && value !== undefined) ? value.substring(0, 50) : ''}`);
      result.success(true);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `setWidgetData failed: ${JSON.stringify(e)}`);
      result.success(false);
    }
  }
}
