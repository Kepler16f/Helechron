import { Want, Configuration } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';
import { ECardNativeHelper, WIDGET_PREFS_NAME, PAYMENT_FORM_IDS_KEY } from './ECardNativeHelper';

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
    this.saveFormId(prefs, formId);
    // 系统定时触发 onUpdateForm 时，也尝试静默刷新一次付款码
    this.refreshFromNetwork(formId);
  }

  /// 卡片内点击“刷新”按钮（postCardAction action:'message'）时触发。
  /// 在原生侧直接重新取码（含墓碑后台/进程被杀时的原生 SSO 自动重登），无需拉起应用。
  onFormEvent(formId: string, message: string): void {
    console.info(`PaymentCodeWidget onFormEvent: formId=${formId}, message=${message}`);
    const prefs = this.getPrefs();
    if (prefs !== null && formId.length > 0) {
      this.saveFormId(prefs, formId);
    }
    if (message.indexOf('refresh_payment_code') >= 0) {
      // 1. 立即给卡片推送“刷新中...”反馈，确保墓碑唤醒或后台点击时有即时视觉响应
      if (prefs !== null) {
        const curCode = (prefs.getSync('paymentCode', '') as string) || '';
        const pendingData: Record<string, string> = {
          'paymentCode': curCode,
          'displayName': '刷新中...',
          'hasCode': curCode.length > 0 ? '1' : '0'
        };
        formProvider.updateForm(formId, formBindingData.createFormBindingData(pendingData)).catch(() => {});
      }
      // 2. 异步发起网络取码（若 synjonesAuth 已过期则自动在原生侧通过统一身份认证重登换码）
      this.refreshFromNetwork(formId);
    } else {
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
    const raw = (prefs.getSync(PAYMENT_FORM_IDS_KEY, '') as string) || '';
    if (!raw) {
      return;
    }
    const ids = raw.split(',').filter((id: string) => id.length > 0);
    for (const id of ids) {
      this.pushData(id, prefs);
    }
  }

  private getPrefs(): preferences.Preferences | null {
    return ECardNativeHelper.getFreshPrefs(this.context);
  }

  private buildData(prefs: preferences.Preferences | null): Record<string, string> {
    let code = '';
    let name = '付款码';
    if (prefs !== null) {
      code = (prefs.getSync('paymentCode', '') as string) || '';
      name = (prefs.getSync('displayName', '付款码') as string) || '付款码';
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
    const raw = (prefs.getSync(PAYMENT_FORM_IDS_KEY, '') as string) || '';
    if (raw.length > 0) {
      const ids = raw.split(',').filter((id: string) => id.length > 0 && id !== currentFormId);
      for (const id of ids) {
        formProvider.updateForm(id, formData).catch((err: BusinessError) => {
          console.error(`PaymentCodeWidget updateForm failed for ${id}: ${err.code} ${err.message}`);
        });
      }
    }
  }

  /// 点击刷新：重新取码（含自动重登）并落盘 + 刷新卡片；失败时回退到本地缓存。
  private async refreshFromNetwork(formId: string): Promise<void> {
    const res = await ECardNativeHelper.fetchBarcodeWithAutoRelogin(this.context);
    const prefs = this.getPrefs();
    if (prefs === null) {
      return;
    }
    if (res.code.length > 0) {
      this.pushToAllForms(prefs, formId);
    } else if (res.authExpired) {
      const curCode = (prefs.getSync('paymentCode', '') as string) || '';
      const noAuthData: Record<string, string> = {
        'paymentCode': curCode,
        'displayName': '请打开应用登录',
        'hasCode': curCode.length > 0 ? '1' : '0'
      };
      formProvider.updateForm(formId, formBindingData.createFormBindingData(noAuthData)).catch(() => {});
    } else {
      // 取码失败：保持原有付款码，恢复标题
      try {
        prefs.putSync('displayName', '付款码');
        prefs.flush();
      } catch (e) {}
      this.pushToAllForms(prefs, formId);
    }
  }

  private saveFormId(prefs: preferences.Preferences, formId: string): void {
    try {
      const raw = (prefs.getSync(PAYMENT_FORM_IDS_KEY, '') as string) || '';
      const ids = raw ? raw.split(',').filter((id: string) => id.length > 0) : [];
      if (!ids.includes(formId)) {
        ids.push(formId);
        prefs.putSync(PAYMENT_FORM_IDS_KEY, ids.join(','));
        prefs.flush();
      }
    } catch (e) {
      // ignore
    }
  }

  private removeFormId(prefs: preferences.Preferences, formId: string): void {
    try {
      const raw = (prefs.getSync(PAYMENT_FORM_IDS_KEY, '') as string) || '';
      if (!raw) {
        return;
      }
      const ids = raw.split(',').filter((id: string) => id !== formId && id.length > 0);
      prefs.putSync(PAYMENT_FORM_IDS_KEY, ids.join(','));
      prefs.flush();
    } catch (e) {
      // ignore
    }
  }
}
