import { FlutterAbility, FlutterEngine, MethodChannel, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import notificationManager from '@ohos.notificationManager';
import hilog from '@ohos.hilog';

const DOMAIN = 0x0000;
const TAG = 'HelechronNative';
const CHANNEL_NAME = 'top.celechron.helechron/native';

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
      case 'syncCalendarEvents':
        this.syncCalendarEvents(call, result);
        break;
      case 'clearCalendarEvents':
        this.clearCalendarEvents(result);
        break;
      case 'checkCalendarPermission':
        this.checkCalendarPermission(result);
        break;
      case 'requestCalendarPermission':
        this.requestCalendarPermission(result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  // ==================== Calendar ====================

  private CALENDAR_NAME = 'Helechron课表';
  private CALENDAR_ACCOUNT_NAME = 'Helechron';
  private CALENDAR_ACCOUNT_TYPE = 'top.celechron.helechron';

  private async getDefaultCalendarId(): Promise<string | null> {
    try {
      const calendars = await import('@ohos.calendar');
      const calendarList = await calendars.getDefaultCalendar(this.context);
      if (calendarList) {
        return calendarList.calendarId;
      }
      return null;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `getDefaultCalendarId failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  private checkCalendarPermission(result: MethodResult): void {
    try {
      const abilityAccessCtrl = import('@ohos.abilityAccessCtrl');
      abilityAccessCtrl.then((module) => {
        const atManager = module.createAtManager();
        atManager.checkAccessToken(this.context.tokenID, 'ohos.permission.READ_CALENDAR')
          .then((permissionResult: number) => {
            result.success(permissionResult === 0);
          })
          .catch(() => {
            result.success(false);
          });
      }).catch(() => {
        result.success(false);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `checkCalendarPermission: calendar API not available`);
      result.success(false);
    }
  }

  private requestCalendarPermission(result: MethodResult): void {
    try {
      const abilityAccessCtrl = import('@ohos.abilityAccessCtrl');
      abilityAccessCtrl.then((module) => {
        const atManager = module.createAtManager();
        atManager.requestPermissionsFromUser(this.context, ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'])
          .then((permissionResult) => {
            const allGranted = permissionResult.authResults.every((r: number) => r === 0);
            result.success(allGranted);
          })
          .catch(() => {
            result.success(false);
          });
      }).catch(() => {
        result.success(false);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `requestCalendarPermission: calendar API not available`);
      result.success(false);
    }
  }

  private async syncCalendarEvents(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const events = call.argument('events') as Array<{
        uid: string;
        summary: string;
        description: string;
        location: string;
        startTime: number;
        endTime: number;
      }>;

      if (!events || events.length === 0) {
        result.success(0);
        return;
      }

      const calendars = await import('@ohos.calendar');
      const calendar = await calendars.getDefaultCalendar(this.context);

      if (!calendar) {
        hilog.error(DOMAIN, TAG, 'No default calendar found');
        result.error('CALENDAR_ERROR', 'No default calendar available', null);
        return;
      }

      let insertedCount = 0;
      for (const event of events) {
        try {
          const calendarEvent: calendars.CalendarEvent = {
            calendarId: calendar.calendarId,
            title: event.summary,
            description: event.description,
            location: event.location,
            startTime: event.startTime,
            endTime: event.endTime,
            isAllDay: false,
            timeZone: 'Asia/Shanghai',
          };

          const eventIds = await calendars.insertEvent(calendar.calendarId, calendarEvent);
          if (eventIds && eventIds.length > 0) {
            insertedCount++;
          }
        } catch (eventErr) {
          hilog.warn(DOMAIN, TAG, `Failed to insert event "${event.summary}": ${JSON.stringify(eventErr)}`);
        }
      }

      hilog.info(DOMAIN, TAG, `Synced ${insertedCount}/${events.length} events to system calendar`);
      result.success(insertedCount);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `syncCalendarEvents failed: ${JSON.stringify(err)}`);
      result.error('CALENDAR_ERROR', `Sync failed: ${JSON.stringify(err)}`, null);
    }
  }

  private async clearCalendarEvents(result: MethodResult): Promise<void> {
    try {
      const calendars = await import('@ohos.calendar');
      const calendar = await calendars.getDefaultCalendar(this.context);

      if (!calendar) {
        result.success(0);
        return;
      }

      const startTime = Date.now() - 365 * 24 * 60 * 60 * 1000;
      const endTime = Date.now() + 365 * 24 * 60 * 60 * 1000;

      const existingEvents = await calendars.getEvents(calendar.calendarId, startTime, endTime);
      let deletedCount = 0;

      if (existingEvents && existingEvents.length > 0) {
        for (const event of existingEvents) {
          try {
            if (event.title && event.title.startsWith('[')) {
              await calendars.deleteEvent(calendar.calendarId, event.eventId);
              deletedCount++;
            }
          } catch (delErr) {
            hilog.warn(DOMAIN, TAG, `Failed to delete event: ${JSON.stringify(delErr)}`);
          }
        }
      }

      hilog.info(DOMAIN, TAG, `Cleared ${deletedCount} synced events from system calendar`);
      result.success(deletedCount);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `clearCalendarEvents failed: ${JSON.stringify(err)}`);
      result.error('CALENDAR_ERROR', `Clear failed: ${JSON.stringify(err)}`, null);
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
        result.error('NOTIFICATION_ERROR', `Failed to publish: ${JSON.stringify(err)}`, null);
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
