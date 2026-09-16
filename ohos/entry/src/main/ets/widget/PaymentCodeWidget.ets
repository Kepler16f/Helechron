import {
  Want
} from '@kit.AbilityKit';
import {
  formBindingData,
  FormExtensionAbility
} from '@kit.FormKit';
import preferences from '@ohos.data.preferences';

const PREFS_NAME = 'helechron_widget_data';

export default class PaymentCodeWidgetExtension extends FormExtensionAbility {
  async onCreateForm(want: Want): Promise<formBindingData.FormBindingData> {
    let code = '10000000000000000001';
    let name = '付款码';
    try {
      const prefs = await preferences.getPreferences(getContext(this), PREFS_NAME);
      const storedCode = await prefs.get('paymentCode', code) as string;
      const storedName = await prefs.get('displayName', name) as string;
      if (storedCode !== null && storedCode !== undefined && storedCode.length > 0) {
        code = storedCode;
      }
      if (storedName !== null && storedName !== undefined && storedName.length > 0) {
        name = storedName;
      }
    } catch (e) {
      // fallback to defaults
    }
    const formData: Record<string, string> = {
      'src': 'ets/widget/pages/PaymentCodeWidget',
      'code': code,
      'name': name
    };
    return formBindingData.createFormBindingData(formData);
  }
}
