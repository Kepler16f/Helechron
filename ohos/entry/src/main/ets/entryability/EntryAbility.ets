import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import notificationManager from '@ohos.notificationManager';
import calendarManager from '@ohos.calendarManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import hilog from '@ohos.hilog';

const DOMAIN = 0x0000;
const TAG = 'HelechronNative';
const CHANNEL_NAME = 'top.celechron.helechron/native';
const CALENDAR_ACCOUNT_NAME = 'helechron';
const CALENDAR_DISPLAY_NAME = 'Helechron课表';
const CALENDAR_TIME_ZONE = 'Asia/Shanghai';
const PERMISSION_READ_CALENDAR = 'ohos.permission.READ_CALENDAR';
const PERMISSION_WRITE_CALENDAR = 'ohos.permission.WRITE_CALENDAR';

interface CalendarEventPayload {
  uid: string;
  summary: string;
  description: string;
  location: string;
  startTime: number;
  endTime: number;
}

export default class EntryAbility extends FlutterAbility {
  private methodChannel: MethodChannel | null = null;

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
        PERMISSION_WRITE_CALENDAR
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
      result.success(allGranted);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `requestCalendarPermission failed: ${JSON.stringify(err)}`);
      result.success(false);
    }
  }

  private getCalendarManagerInstance(): calendarManager.CalendarManager {
    return calendarManager.getCalendarManager(this.context);
  }

  private async getOrCreateCalendar(): Promise<calendarManager.Calendar> {
    const manager = this.getCalendarManagerInstance();
    hilog.info(DOMAIN, TAG, 'getOrCreateCalendar: listing all calendars');
    const calendars = await manager.getAllCalendars();
    hilog.info(DOMAIN, TAG, `getOrCreateCalendar: found ${calendars.length} calendars`);
    for (let i = 0; i < calendars.length; i++) {
      const account = calendars[i].getAccount();
      hilog.info(DOMAIN, TAG, `  calendar[${i}]: name=${account.name}, type=${account.type}`);
      if (account.name === CALENDAR_ACCOUNT_NAME) {
        hilog.info(DOMAIN, TAG, 'getOrCreateCalendar: found existing Helechron calendar');
        return calendars[i];
      }
    }
    hilog.info(DOMAIN, TAG, 'getOrCreateCalendar: creating new Helechron calendar');
    const account: calendarManager.CalendarAccount = {
      name: CALENDAR_ACCOUNT_NAME,
      type: calendarManager.CalendarType.LOCAL,
      displayName: CALENDAR_DISPLAY_NAME
    };
    try {
      const newCalendar = await manager.createCalendar(account);
      hilog.info(DOMAIN, TAG, 'getOrCreateCalendar: new calendar created successfully');
      return newCalendar;
    } catch (createErr) {
      hilog.warn(DOMAIN, TAG, `getOrCreateCalendar: createCalendar failed (${JSON.stringify(createErr)}), falling back to default calendar`);
      return await manager.getCalendar();
    }
  }

  private async hasSyncedCalendar(result: MethodResult): Promise<void> {
    try {
      const manager = this.getCalendarManagerInstance();
      const calendars = await manager.getAllCalendars();
      let found = false;
      for (let i = 0; i < calendars.length; i++) {
        const account = calendars[i].getAccount();
        if (account.name === CALENDAR_ACCOUNT_NAME) {
          found = true;
          break;
        }
      }
      hilog.info(DOMAIN, TAG, `hasSyncedCalendar: ${found}`);
      result.success(found);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `hasSyncedCalendar failed: ${JSON.stringify(err)}`);
      result.success(false);
    }
  }

  private syncCalendarEvents(call: MethodCall, result: MethodResult): void {
    const payloads = call.argument('events') as CalendarEventPayload[];
    if (payloads === null || payloads === undefined || payloads.length === 0) {
      hilog.info(DOMAIN, TAG, 'syncCalendarEvents: no events to sync');
      result.success(0);
      return;
    }
    hilog.info(DOMAIN, TAG, `syncCalendarEvents: received ${payloads.length} events`);
    this.doCalendarSync(payloads, result);
  }

  private async doCalendarSync(payloads: CalendarEventPayload[], result: MethodResult): Promise<void> {
    try {
      const calendar = await this.getOrCreateCalendar();
      const events: calendarManager.Event[] = [];
      for (let i = 0; i < payloads.length; i++) {
        const payload = payloads[i];
        const event: calendarManager.Event = {
          type: calendarManager.EventType.NORMAL,
          title: payload.summary,
          location: { location: payload.location },
          startTime: payload.startTime,
          endTime: payload.endTime,
          isAllDay: false,
          timeZone: CALENDAR_TIME_ZONE,
          description: payload.description,
          identifier: payload.uid
        };
        events.push(event);
      }
      hilog.info(DOMAIN, TAG, `doCalendarSync: adding ${events.length} events to calendar`);
      await calendar.addEvents(events);
      hilog.info(DOMAIN, TAG, `doCalendarSync: successfully synced ${events.length} events`);
      result.success(events.length);
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
      const manager = this.getCalendarManagerInstance();
      const calendars = await manager.getAllCalendars();
      let deletedCount = 0;
      for (let i = 0; i < calendars.length; i++) {
        const account = calendars[i].getAccount();
        if (account.name === CALENDAR_ACCOUNT_NAME) {
          await manager.deleteCalendar(calendars[i]);
          deletedCount++;
        }
      }
      hilog.info(DOMAIN, TAG, `doClearCalendarEvents: cleared ${deletedCount} Helechron calendars`);
      result.success(deletedCount);
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
}
