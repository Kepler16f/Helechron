import { Want, Configuration } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';
import { buildSimpleCourseFormData, scheduleSimpleBoundary } from './SimpleCourseStateHelper';

const PREFS_NAME = 'helechron_widget_data';
const FORM_IDS_KEY = 'simple_course_form_ids';

export default class SimpleCourseWidgetExtension extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId = '';
    if (want.parameters) {
      formId = String(want.parameters[formInfo.FormParam.IDENTITY_KEY] || '');
    }
    const prefs = this.getPrefs();
    if (prefs !== null) {
      if (formId.length > 0) {
        this.saveFormId(prefs, formId);
        scheduleSimpleBoundary(formId, prefs);
      }
      return formBindingData.createFormBindingData(buildSimpleCourseFormData(prefs));
    }
    const empty: Record<string, string> = {
      'courseName': '今日暂无课程',
      'courseStatus': '全部结课',
      'courseStatusColor': '#888888',
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
    scheduleSimpleBoundary(formId, prefs);
  }

  onFormEvent(formId: string, message: string): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    console.info(`SimpleCourseWidget onFormEvent: formId=${formId}, message=${message}`);
    this.pushFormData(formId, prefs);
    scheduleSimpleBoundary(formId, prefs);
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
      console.error(`SimpleCourseWidget getPrefs failed: ${JSON.stringify(e)}`);
      return null;
    }
  }

  private pushFormData(formId: string, prefs: preferences.Preferences): void {
    const formData = formBindingData.createFormBindingData(buildSimpleCourseFormData(prefs));
    formProvider.updateForm(formId, formData).catch((err: BusinessError) => {
      console.error(`SimpleCourseWidget updateForm failed: ${err.code} ${err.message}`);
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
