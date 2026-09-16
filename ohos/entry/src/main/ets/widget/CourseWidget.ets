import {
  Want
} from '@kit.AbilityKit';
import {
  formBindingData,
  FormExtensionAbility,
  formProvider
} from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';

const PREFS_NAME = 'helechron_widget_data';

export default class CourseWidgetExtension extends FormExtensionAbility {
  async onCreateForm(want: Want): Promise<formBindingData.FormBindingData> {
    let courseData = '';
    try {
      const prefs = await preferences.getPreferences(getContext(this), PREFS_NAME);
      const stored = await prefs.get('nextCourse', '') as string;
      if (stored !== null && stored !== undefined) {
        courseData = stored;
      }
    } catch (e) {
      // use defaults
    }
    const data: Record<string, string> = {
      'courseData': courseData
    };
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshFormData(formId);
  }

  private async refreshFormData(formId: string): Promise<void> {
    let courseData = '';
    try {
      const prefs = await preferences.getPreferences(getContext(this), PREFS_NAME);
      const stored = await prefs.get('nextCourse', '') as string;
      if (stored !== null && stored !== undefined) {
        courseData = stored;
      }
    } catch (e) {
      // use defaults
    }
    const data: Record<string, string> = {
      'courseData': courseData
    };
    const formData = formBindingData.createFormBindingData(data);
    formProvider.updateForm(formId, formData).catch((err: BusinessError) => {
      console.error(`CourseWidget updateForm failed: ${err.code} ${err.message}`);
    });
  }
}
