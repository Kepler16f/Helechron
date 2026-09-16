import {
  Want
} from '@kit.AbilityKit';
import {
  hilog
} from '@kit.PerformanceAnalysisKit';
import {
  formBindingData,
  FormExtensionAbility
} from '@kit.FormKit';

const DOMAIN = 0x0000;
const TAG = 'CourseWidgetExt';

export default class CourseWidgetExtension extends FormExtensionAbility {
  onCreateForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'CourseWidget onCreateForm');
    const data = AppStorage.Get<string>('nextCourse') || '';
    const formData: Record<string, Object> = {
      'src': 'ets/widget/pages/CourseWidget',
      'data': data
    };
    return formBindingData.createFormBindingData(formData);
  }

  onUpdateForm(formId: number): void {
    hilog.info(DOMAIN, TAG, `onUpdateForm: ${formId}`);
  }

  onDestroyForm(formId: number): void {
    hilog.info(DOMAIN, TAG, `onDestroyForm: ${formId}`);
  }
}
