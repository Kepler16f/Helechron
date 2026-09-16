import {
  Want
} from '@kit.AbilityKit';
import {
  formBindingData,
  FormExtensionAbility
} from '@kit.FormKit';
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
      // fallback to empty
    }
    const formData: Record<string, string> = {
      'src': 'ets/widget/pages/CourseWidget',
      'courseData': courseData
    };
    return formBindingData.createFormBindingData(formData);
  }
}
