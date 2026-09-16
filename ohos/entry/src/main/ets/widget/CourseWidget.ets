import {
  Want
} from '@kit.AbilityKit';
import {
  formBindingData,
  FormExtensionAbility
} from '@kit.FormKit';

export default class CourseWidgetExtension extends FormExtensionAbility {
  onCreateForm(want: Want): formBindingData.FormBindingData {
    const formData: Record<string, string> = {
      'src': 'ets/widget/pages/CourseWidget',
      'data': ''
    };
    return formBindingData.createFormBindingData(formData);
  }
}
