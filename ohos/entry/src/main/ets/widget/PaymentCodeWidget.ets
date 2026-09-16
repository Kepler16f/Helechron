import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';

const PREFS_NAME = 'helechron_widget_data';
const FORM_IDS_KEY = 'payment_form_ids';

export default class PaymentCodeWidgetExtension extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId = '';
    if (want.parameters) {
      formId = String(want.parameters[formInfo.FormParam.IDENTITY_KEY] || '');
    }

    let code = '';
    let name = '浙大校园卡付款码';
    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      if (formId.length > 0) {
        this.saveFormId(prefs, formId);
      }
      code = prefs.getSync('paymentCode', '') as string;
      name = prefs.getSync('displayName', '浙大校园卡付款码') as string;
    } catch (e) {
      // ignore
    }

    const data: Record<string, string> = {
      'paymentCode': code,
      'displayName': name,
      'hasCode': code.length > 0 ? '1' : '0'
    };
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.refreshFormData(formId);
  }

  onRemoveForm(formId: string): void {
    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      this.removeFormId(prefs, formId);
    } catch (e) {
      // ignore
    }
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
      if (!raw) return;
      const ids = raw.split(',').filter((id: string) => id !== formId && id.length > 0);
      prefs.putSync(FORM_IDS_KEY, ids.join(','));
      prefs.flush();
    } catch (e) {
      // ignore
    }
  }

  private refreshFormData(formId: string): void {
    let code = '';
    let name = '浙大校园卡付款码';
    try {
      const prefs = preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
      code = prefs.getSync('paymentCode', '') as string;
      name = prefs.getSync('displayName', '浙大校园卡付款码') as string;
    } catch (e) {
      // ignore
    }
    const data: Record<string, string> = {
      'paymentCode': code,
      'displayName': name,
      'hasCode': code.length > 0 ? '1' : '0'
    };
    const formData = formBindingData.createFormBindingData(data);
    formProvider.updateForm(formId, formData).catch((err: BusinessError) => {
      console.error(`PaymentCodeWidget updateForm failed: ${err.code} ${err.message}`);
    });
  }
}
