import { Want, Configuration } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import preferences from '@ohos.data.preferences';

const PREFS_NAME = 'helechron_widget_data';
const FORM_IDS_KEY = 'payment_form_ids';
const TEST_ACCOUNT = '3200000000';
const BARCODE_URL_PREFIX =
  'https://elife.zju.edu.cn/berserker-app/ykt/tsm/batchGetBarCodeGet?account=';
const BARCODE_URL_SUFFIX = '&payacc=%23%23%23&paytype=1&synAccessSource=app';

export default class PaymentCodeWidgetExtension extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId = '';
    if (want.parameters) {
      formId = String(want.parameters[formInfo.FormParam.IDENTITY_KEY] || '');
    }

    const prefs = this.getPrefs();
    if (prefs !== null && formId.length > 0) {
      this.saveFormId(prefs, formId);
    }
    return formBindingData.createFormBindingData(this.buildData(prefs));
  }

  onUpdateForm(formId: string): void {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    this.pushData(formId, prefs);
  }

  /// 卡片内点击“刷新”按钮（postCardAction action:'message'）时触发。
  /// 在原生侧直接重新取码，无需拉起应用。
  onFormEvent(formId: string, message: string): void {
    console.info(`PaymentCodeWidget onFormEvent: formId=${formId}, message=${message}`);
    if (message.indexOf('refresh_payment_code') >= 0) {
      this.refreshFromNetwork(formId);
    } else {
      const prefs = this.getPrefs();
      if (prefs !== null) {
        this.pushData(formId, prefs);
      }
    }
  }

  onRemoveForm(formId: string): void {
    const prefs = this.getPrefs();
    if (prefs !== null) {
      this.removeFormId(prefs, formId);
    }
  }

  onConfigurationUpdate(config: Configuration): void {
    // 深浅色模式或语言变化时，强制刷新所有小组件以重新解析主题色
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
      this.pushData(id, prefs);
    }
  }

  private getPrefs(): preferences.Preferences | null {
    try {
      return preferences.getPreferencesSync(this.context, { name: PREFS_NAME });
    } catch (e) {
      console.error(`PaymentCodeWidget getPrefs failed: ${JSON.stringify(e)}`);
      return null;
    }
  }

  private buildData(prefs: preferences.Preferences | null): Record<string, string> {
    let code = '';
    let name = '付款码';
    if (prefs !== null) {
      code = prefs.getSync('paymentCode', '') as string;
      name = prefs.getSync('displayName', '付款码') as string;
    }
    const data: Record<string, string> = {
      'paymentCode': code,
      'displayName': name,
      'hasCode': code.length > 0 ? '1' : '0'
    };
    return data;
  }

  private pushData(formId: string, prefs: preferences.Preferences): void {
    const formData = formBindingData.createFormBindingData(this.buildData(prefs));
    formProvider.updateForm(formId, formData).catch((err: BusinessError) => {
      console.error(`PaymentCodeWidget updateForm failed: ${err.code} ${err.message}`);
    });
  }

  /// 点击刷新：重新取码并落盘 + 刷新卡片；失败时回退到本地缓存。
  private async refreshFromNetwork(formId: string): Promise<void> {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    const code = await this.fetchBarcode(prefs);
    if (code.length > 0) {
      try {
        prefs.putSync('paymentCode', code);
        prefs.flush();
      } catch (e) {
        // ignore
      }
      this.pushData(formId, prefs);
    } else {
      // 取码失败：保持原有付款码，仅按本地缓存刷新
      this.pushData(formId, prefs);
    }
  }

  private async fetchBarcode(prefs: preferences.Preferences): Promise<string> {
    const auth = prefs.getSync('synjonesAuth', '') as string;
    const account = prefs.getSync('eCardAccount', '') as string;
    if (auth.length === 0) {
      return '';
    }
    // 测试账号：生成模拟付款码，便于本地预览
    if (auth === TEST_ACCOUNT || account === TEST_ACCOUNT) {
      let code = '';
      for (let i = 0; i < 16; i++) {
        code += Math.floor(Math.random() * 10).toString();
      }
      return code;
    }

    const httpRequest = http.createHttp();
    try {
      const url = `${BARCODE_URL_PREFIX}${account}${BARCODE_URL_SUFFIX}`;
      const header: Record<string, string> = { 'synjones-auth': `bearer ${auth}` };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: header,
        connectTimeout: 8000,
        readTimeout: 8000,
        expectDataType: http.HttpDataType.STRING
      };
      const response = await httpRequest.request(url, options);
      if (response.responseCode !== 200) {
        console.error(`PaymentCodeWidget fetchBarcode http ${response.responseCode}`);
        return '';
      }
      const text = response.result as string;
      const payload = JSON.parse(text) as Record<string, Object>;
      const data = payload['data'] as Record<string, Object>;
      if (data === undefined || data === null) {
        return '';
      }
      const barcodes = data['barcode'] as string[];
      if (barcodes !== undefined && barcodes !== null && barcodes.length > 0) {
        return barcodes[0];
      }
      return '';
    } catch (e) {
      console.error(`PaymentCodeWidget fetchBarcode failed: ${JSON.stringify(e)}`);
      return '';
    } finally {
      httpRequest.destroy();
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
