import {
  Want
} from '@kit.AbilityKit';
import {
  formBindingData,
  FormExtensionAbility
} from '@kit.FormKit';

export default class PaymentCodeWidgetExtension extends FormExtensionAbility {
  onCreateForm(want: Want): formBindingData.FormBindingData {
    const formData: Record<string, string> = {
      'src': 'ets/widget/pages/PaymentCodeWidget',
      'data': '10000000000000000001'
    };
    return formBindingData.createFormBindingData(formData);
  }

  onUpdateForm(formId: number): void {
    // refresh if needed
  }

  onDestroyForm(formId: number): void {
    // cleanup
  }
}
