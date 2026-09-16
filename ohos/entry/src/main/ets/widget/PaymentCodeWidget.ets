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
const TAG = 'PaymentCodeWidgetExt';

export default class PaymentCodeWidgetExtension extends FormExtensionAbility {
  onCreateForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, 'PaymentCodeWidget onCreateForm');
    const data = AppStorage.Get<string>('paymentCode') || '10000000000000000001';
    const formData: Record<string, Object> = {
      'src': 'ets/widget/pages/PaymentCodeWidget',
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
