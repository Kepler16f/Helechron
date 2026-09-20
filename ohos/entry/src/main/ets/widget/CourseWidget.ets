import { Want, Configuration } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';
import { buildCourseFormData, scheduleNextBoundary } from './CourseStateHelper';

const PREFS_NAME = 'helechron_widget_data';
const FORM_IDS_KEY = 'course_form_ids';

export default class CourseWidgetExtension extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId = '';
    if (want.parameters) {
      formId = String(want.parameters[formInfo.FormParam.IDENTITY_KEY] || '');
    }
    const prefs = this.getPrefs();
    if (prefs !== null) {
      if (formId.length > 0) {
        this.saveFormId(prefs, formId);
        scheduleNextBoundary(formId, prefs);
      }
      return formBindingData.createFormBindingData(buildCourseFormData(prefs));
    }
    const empty: Record<string, string> = {
      'courseName': '今日暂无课程',
      'courseStatus': '全部结课',
      'courseStatusColor': '#888888',
      'courseStatusTime': '',
      'progressPercent': '0',
      'progressColor': '#1E88E5',
      'showProgress': '0',
      'hasCourse': '0'
    };
    return formBindingData.createFormBindingData(empty);
  }

  onUpdateForm(formId: string): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    this.pushFormData(formId, prefs);
    // 系统刷新后，重新预调度下一个课程边界
    scheduleNextBoundary(formId, prefs);
  }

  onFormEvent(formId: string, message: string): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    console.info(`CourseWidget onFormEvent: formId=${formId}, message=${message}`);
    this.pushFormData(formId, prefs);
    // 用户交互后，重新预调度下一个课程边界
    scheduleNextBoundary(formId, prefs);
  }

  onRemoveForm(formId: string): void {
    const prefs = this.getPrefs();
    if (prefs !== null) {
      this.removeFormId(prefs, formId);
    }
  }

  onConfigurationUpdate(config: Configuration): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    const raw = prefs.getSync(FORM_IDS_KEY, '') as string;
    if (!raw) {
      return;
    }
    const ids = raw.split(',').filter((id: string) => id.length > 0);
    for (const id of ids) {
      this.pushFormData(id, prefs);
    }
  }

  private getPrefs(): preferences.Preferences | null {
    try {
      return preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
    } catch (e) {
      console.error(`CourseWidget getPrefs failed: ${JSON.stringify(e)}`);
      return null;
    }
  }

  private pushFormData(formId: string, prefs: preferences.Preferences): void {
    const formData = formBindingData.createFormBindingData(buildCourseFormData(prefs));
    formProvider.updateForm(formId, formData).catch((err: BusinessError) => {
      console.error(`CourseWidget updateForm failed: ${err.code} ${err.message}`);
    });
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
      if (!raw) {
        return;
      }
      const ids = raw.split(',').filter((id: string) => id !== formId && id.length > 0);
      prefs.putSync(FORM_IDS_KEY, ids.join(','));
      prefs.flush();
    } catch (e) {
      // ignore
    }
  }
}
