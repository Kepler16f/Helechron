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
const USER_AGENT = 'E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)';

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
      // 1. 立即给卡片推送“刷新中...”反馈，确保墓碑唤醒或后台点击时有即时视觉响应
      const prefs = this.getPrefs();
      if (prefs !== null) {
        const curCode = prefs.getSync('paymentCode', '') as string;
        const pendingData: Record<string, string> = {
          'paymentCode': curCode,
          'displayName': '刷新中...',
          'hasCode': curCode.length > 0 ? '1' : '0'
        };
        formProvider.updateForm(formId, formBindingData.createFormBindingData(pendingData)).catch(() => {});
      }
      // 2. 异步发起网络取码并推送
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

  private pushToAllForms(prefs: preferences.Preferences, currentFormId?: string): void {
    const formData = formBindingData.createFormBindingData(this.buildData(prefs));
    if (currentFormId && currentFormId.length > 0) {
      formProvider.updateForm(currentFormId, formData).catch((err: BusinessError) => {
        console.error(`PaymentCodeWidget updateForm failed for ${currentFormId}: ${err.code} ${err.message}`);
      });
    }
    const raw = prefs.getSync(FORM_IDS_KEY, '') as string;
    if (raw.length > 0) {
      const ids = raw.split(',').filter((id: string) => id.length > 0 && id !== currentFormId);
      for (const id of ids) {
        formProvider.updateForm(id, formData).catch((err: BusinessError) => {
          console.error(`PaymentCodeWidget updateForm failed for ${id}: ${err.code} ${err.message}`);
        });
      }
    }
  }

  /// 点击刷新：重新取码并落盘 + 刷新卡片；失败时回退到本地缓存。
  private async refreshFromNetwork(formId: string): Promise<void> {
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    const auth = prefs.getSync('synjonesAuth', '') as string;
    if (auth.length === 0) {
      const curCode = prefs.getSync('paymentCode', '') as string;
      const noAuthData: Record<string, string> = {
        'paymentCode': curCode,
        'displayName': '请先打开应用登录',
        'hasCode': curCode.length > 0 ? '1' : '0'
      };
      formProvider.updateForm(formId, formBindingData.createFormBindingData(noAuthData)).catch(() => {});
      return;
    }

    const code = await this.fetchBarcode(prefs);
    if (code.length > 0) {
      try {
        prefs.putSync('paymentCode', code);
        prefs.putSync('displayName', '付款码');
        prefs.flush();
      } catch (e) {
        // ignore
      }
      this.pushToAllForms(prefs, formId);
    } else {
      // 取码失败：保持原有付款码，恢复标题
      try {
        prefs.putSync('displayName', '付款码');
        prefs.flush();
      } catch (e) {}
      this.pushToAllForms(prefs, formId);
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

    const url = `${BARCODE_URL_PREFIX}${account}${BARCODE_URL_SUFFIX}`;
    const header: Record<string, string> = {
      'synjones-auth': `bearer ${auth}`,
      'User-Agent': USER_AGENT,
      'Accept': 'application/json, text/plain, */*',
      'Connection': 'keep-alive',
      'Cache-Control': 'no-cache'
    };

    for (let attempt = 1; attempt <= 2; attempt++) {
      const httpRequest = http.createHttp();
      try {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: header,
          connectTimeout: 6000,
          readTimeout: 6500,
          expectDataType: http.HttpDataType.STRING
        };
        const response = await httpRequest.request(url, options);
        if (response.responseCode === 200) {
          const text = response.result as string;
          const payload = JSON.parse(text) as Record<string, Object>;
          const data = payload['data'] as Record<string, Object>;
          if (data !== undefined && data !== null) {
            const barcodes = data['barcode'] as string[];
            if (barcodes !== undefined && barcodes !== null && barcodes.length > 0) {
              const barcode = barcodes[0];
              if (barcode.length >= 14 && barcode.length <= 64) {
                return barcode;
              }
            }
          }
        } else {
          console.error(`PaymentCodeWidget fetchBarcode http ${response.responseCode}`);
        }
      } catch (e) {
        console.error(`PaymentCodeWidget fetchBarcode attempt ${attempt} failed: ${JSON.stringify(e)}`);
      } finally {
        httpRequest.destroy();
      }

      if (attempt < 2) {
        await new Promise<void>((resolve) => setTimeout(resolve, 300));
      }
    }
    return '';
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
