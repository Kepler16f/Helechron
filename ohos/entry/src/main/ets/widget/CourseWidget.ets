import { Want, Configuration } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';

const PREFS_NAME = 'helechron_widget_data';
const FORM_IDS_KEY = 'course_form_ids';

export default class CourseWidgetExtension extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId = '';
    if (want.parameters) {
      formId = String(want.parameters[formInfo.FormParam.IDENTITY_KEY] || '');
    }

    let courseName = '今日暂无课程';
    let courseTime = '';
    let courseLocation = '';
    let courseTeacher = '';
    let courseStatus = '全部结课';
    let courseStatusColor = '#888888';
    let courseStatusTime = '';
    let progressPercent = '0';
    let progressColor = '#1E88E5';
    let hasCourse = '0';

    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      if (formId.length > 0) {
        this.saveFormId(prefs, formId);
      }
      courseName = prefs.getSync('courseName', '今日暂无课程') as string;
      courseTime = prefs.getSync('courseTime', '') as string;
      courseLocation = prefs.getSync('courseLocation', '') as string;
      courseTeacher = prefs.getSync('courseTeacher', '') as string;
      courseStatus = prefs.getSync('courseStatus', '全部结课') as string;
      courseStatusColor = prefs.getSync('courseStatusColor', '#888888') as string;
      courseStatusTime = prefs.getSync('courseStatusTime', '') as string;
      progressPercent = prefs.getSync('progressPercent', '0') as string;
      progressColor = prefs.getSync('progressColor', '#1E88E5') as string;
      hasCourse = prefs.getSync('hasCourse', '0') as string;
    } catch (e) {
      // ignore
    }

    const data: Record<string, string> = {
      'courseName': courseName,
      'courseTime': courseTime,
      'courseLocation': courseLocation,
      'courseTeacher': courseTeacher,
      'courseStatus': courseStatus,
      'courseStatusColor': courseStatusColor,
      'courseStatusTime': courseStatusTime,
      'progressPercent': progressPercent,
      'progressColor': progressColor,
      'hasCourse': hasCourse
    };
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshFormData(formId);
  }

  onRemoveForm(formId: string): void {
    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      this.removeFormId(prefs, formId);
    } catch (e) {
      // ignore
    }
  }

  onConfigurationUpdate(config: Configuration): void {
    // 深浅色模式或语言变化时，强制刷新所有小组件以重新解析主题色
    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      const raw = prefs.getSync(FORM_IDS_KEY, '') as string;
      if (!raw) {
        return;
      }
      const ids = raw.split(',').filter((id: string) => id.length > 0);
      for (const id of ids) {
        this.refreshFormData(id);
      }
    } catch (e) {
      // ignore
    }
  }

  private saveFormId(prefs: preferences.Preferences, formId: string): void {
    try {
      const raw = prefs.getSync(FORM_IDS_KEY, '') as string;
      const ids = raw ? raw.split(',').filter((id: string) => id.length > 0) : [];
      if (!ids.includes(formId)) {
        ids.push(formId);
        prefs.putSync(FORM_IDS_KEY, ids.join(','));
        prefs.flush();
      }
    } catch (e) {
      // ignore
    }
  }

  private removeFormId(prefs: preferences.Preferences, formId: string): void {
    try {
      const raw = prefs.getSync(FORM_IDS_KEY, '') as string;
      if (!raw) return;
      const ids = raw.split(',').filter((id: string) => id !== formId && id.length > 0);
      prefs.putSync(FORM_IDS_KEY, ids.join(','));
      prefs.flush();
    } catch (e) {
      // ignore
    }
  }

  private refreshFormData(formId: string): void {
    let courseName = '今日暂无课程';
    let courseTime = '';
    let courseLocation = '';
    let courseTeacher = '';
    let courseStatus = '全部结课';
    let courseStatusColor = '#888888';
    let courseStatusTime = '';
    let progressPercent = '0';
    let progressColor = '#1E88E5';
    let hasCourse = '0';

    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      courseName = prefs.getSync('courseName', '今日暂无课程') as string;
      courseTime = prefs.getSync('courseTime', '') as string;
      courseLocation = prefs.getSync('courseLocation', '') as string;
      courseTeacher = prefs.getSync('courseTeacher', '') as string;
      courseStatus = prefs.getSync('courseStatus', '全部结课') as string;
      courseStatusColor = prefs.getSync('courseStatusColor', '#888888') as string;
      courseStatusTime = prefs.getSync('courseStatusTime', '') as string;
      progressPercent = prefs.getSync('progressPercent', '0') as string;
      progressColor = prefs.getSync('progressColor', '#1E88E5') as string;
      hasCourse = prefs.getSync('hasCourse', '0') as string;
    } catch (e) {
      // ignore
    }

    const data: Record<string, string> = {
      'courseName': courseName,
      'courseTime': courseTime,
      'courseLocation': courseLocation,
      'courseTeacher': courseTeacher,
      'courseStatus': courseStatus,
      'courseStatusColor': courseStatusColor,
      'courseStatusTime': courseStatusTime,
      'progressPercent': progressPercent,
      'progressColor': progressColor,
      'hasCourse': hasCourse
    };
    const formData = formBindingData.createFormBindingData(data);
    formProvider.updateForm(formId, formData).catch((err: BusinessError) => {
      console.error(`CourseWidget updateForm failed: ${err.code} ${err.message}`);
    });
  }
}
