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

export default class PaymentCodeWidgetExtension extends FormExtensionAbility {
  async onCreateForm(want: Want): Promise<formBindingData.FormBindingData> {
    let code = '10000000000000000001';
    let name = '付款码';
    try {
      const prefs = await preferences.getPreferences(getContext(this), PREFS_NAME);
      const storedCode = await prefs.get('paymentCode', '') as string;
      const storedName = await prefs.get('displayName', '') as string;
      if (storedCode.length > 0) {
        code = storedCode;
      }
      if (storedName.length > 0) {
        name = storedName;
      }
    } catch (e) {
      // use defaults
    }
    const data: Record<string, string> = {
      'paymentCode': code,
      'displayName': name
    };
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshFormData(formId);
  }

  private async refreshFormData(formId: string): Promise<void> {
    let code = '10000000000000000001';
    let name = '付款码';
    try {
      const prefs = await preferences.getPreferences(getContext(this), PREFS_NAME);
      const storedCode = await prefs.get('paymentCode', '') as string;
      const storedName = await prefs.get('displayName', '') as string;
      if (storedCode.length > 0) {
        code = storedCode;
      }
      if (storedName.length > 0) {
        name = storedName;
      }
    } catch (e) {
      // use defaults
    }
    const data: Record<string, string> = {
      'paymentCode': code,
      'displayName': name
    };
    const formData = formBindingData.createFormBindingData(data);
    formProvider.updateForm(formId, formData).catch((err: BusinessError) => {
      console.error(`PaymentCodeWidget updateForm failed: ${err.code} ${err.message}`);
    });
  }
}
