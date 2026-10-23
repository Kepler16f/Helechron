import common from '@ohos.app.ability.common';
import { http } from '@kit.NetworkKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import preferences from '@ohos.data.preferences';
import hilog from '@ohos.hilog';

const DOMAIN = 0x0000;
const TAG = 'HelechronECardNative';
export const WIDGET_PREFS_NAME = 'helechron_widget_data';
export const PAYMENT_FORM_IDS_KEY = 'payment_form_ids';
export const TEST_ACCOUNT = '3200000000';

const CAS_LOGIN_URL = 'https://zjuam.zju.edu.cn/cas/login';
const CAS_PUBKEY_URL = 'https://zjuam.zju.edu.cn/cas/v2/getPubKey';
const ELIFE_OAUTH_URL =
  'https://elife.zju.edu.cn/berserker-auth/cas/oauth2?resultUrl=https://elife.zju.edu.cn/plat-pc';
const CAMPUS_CARDS_URL =
  'https://elife.zju.edu.cn/berserker-app/ykt/tsm/getCampusCards';
const BARCODE_URL_PREFIX =
  'https://elife.zju.edu.cn/berserker-app/ykt/tsm/batchGetBarCodeGet?account=';
const BARCODE_URL_SUFFIX = '&payacc=%23%23%23&paytype=1&synAccessSource=app';
const USER_AGENT = 'E-CampusZJU/2.3.20 (iPhone; iOS 17.5.1; Scale/3.00)';

export interface BarcodeFetchResult {
  code: string;
  relogged: boolean;
  errorMessage: string;
  authExpired: boolean;
}

interface SingleHopResponse {
  statusCode: number;
  body: string;
  locations: string[];
  synjonesAuth: string;
}

interface ReloginCredentials {
  synjonesAuth: string;
  eCardAccount: string;
}

export class ECardNativeHelper {
  /// 获取最新持久化的 Preferences（先清除内存缓存，确保跨 Ability / FormExtension 进程读取到最新落盘数据）
  static getFreshPrefs(context: common.Context): preferences.Preferences | null {
    try {
      try {
        preferences.removePreferencesFromCacheSync(context, WIDGET_PREFS_NAME);
      } catch (e) {
        // ignore
      }
      return preferences.getPreferencesSync(context, { name: WIDGET_PREFS_NAME });
    } catch (e) {
      hilog.error(DOMAIN, TAG, `getFreshPrefs failed: ${JSON.stringify(e)}`);
      return null;
    }
  }

  /// 同步刷新所有已添加的桌面付款码小组件
  static pushPaymentCodeToAllWidgets(prefs: preferences.Preferences, code: string, displayName: string = '付款码'): void {
    try {
      const rawIds: string = (prefs.getSync(PAYMENT_FORM_IDS_KEY, '') as string) || '';
      if (rawIds.length === 0) {
        return;
      }
      const ids: string[] = rawIds.split(',').filter((id: string) => id.length > 0);
      const payData: Record<string, string> = {
        'paymentCode': code,
        'displayName': displayName,
        'hasCode': code.length > 0 ? '1' : '0'
      };
      const bindingData: formBindingData.FormBindingData = formBindingData.createFormBindingData(payData);
      for (const formId of ids) {
        formProvider.updateForm(formId, bindingData).catch((err: BusinessError) => {
          hilog.warn(DOMAIN, TAG, `updateForm failed for ${formId}: ${err.message}`);
        });
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `pushPaymentCodeToAllWidgets error: ${JSON.stringify(e)}`);
    }
  }

  /// 核心取码入口：优先使用现有 synjonesAuth 取码；
  /// 若应用在后台被杀或进入墓碑后台导致 synjonesAuth 过期/缺失，则自动在原生侧完成统一身份认证重登并换取新码。
  static async fetchBarcodeWithAutoRelogin(context: common.Context): Promise<BarcodeFetchResult> {
    const prefs = ECardNativeHelper.getFreshPrefs(context);
    if (prefs === null) {
      return {
        code: '',
        relogged: false,
        errorMessage: '无法读取本地配置存储',
        authExpired: false
      };
    }

    let auth: string = (prefs.getSync('synjonesAuth', '') as string) || '';
    let account: string = (prefs.getSync('eCardAccount', '') as string) || '';
    let username: string = (prefs.getSync('zjuUsername', '') as string) || '';
    let password: string = (prefs.getSync('zjuPassword', '') as string) || '';

    // 若 preferences 中尚未同步学号密码（例如刚升级完尚未打开主界面），尝试从 Hive 安全存储文件中兜底提取
    if (username.length === 0 || password.length === 0) {
      const hiveCreds = ECardNativeHelper.tryExtractCredentialsFromHive(context);
      if (hiveCreds[0].length > 0 && hiveCreds[1].length > 0) {
        username = hiveCreds[0];
        password = hiveCreds[1];
        try {
          prefs.putSync('zjuUsername', username);
          prefs.putSync('zjuPassword', password);
          prefs.flush();
        } catch (e) {}
      }
      if (auth.length === 0 && hiveCreds[2].length > 0) {
        auth = hiveCreds[2];
      }
      if (account.length === 0 && hiveCreds[3].length > 0) {
        account = hiveCreds[3];
      }
    }

    if (auth.length === 0 && (username.length === 0 || password.length === 0)) {
      return {
        code: '',
        relogged: false,
        errorMessage: '未检测到校园卡登录态，请打开应用并在「设置 → 校园卡账户」中完成登录。',
        authExpired: true
      };
    }

    // 测试账号处理
    if (auth === TEST_ACCOUNT || account === TEST_ACCOUNT || username === TEST_ACCOUNT) {
      let mockCode = '';
      for (let i = 0; i < 20; i++) {
        mockCode += Math.floor(Math.random() * 10).toString();
      }
      ECardNativeHelper.saveAndBroadcastCode(prefs, mockCode);
      return {
        code: mockCode,
        relogged: false,
        errorMessage: '',
        authExpired: false
      };
    }

    // 1. 若已有 synjonesAuth，先尝试直接取码（最快路径 ~200ms）
    let firstError = '';
    if (auth.length > 0) {
      try {
        if (account.length === 0) {
          account = await ECardNativeHelper.fetchCampusCardAccount(auth);
          if (account.length > 0) {
            prefs.putSync('eCardAccount', account);
            prefs.flush();
          }
        }
        if (account.length > 0) {
          const directCode = await ECardNativeHelper.requestBarcodeWithRetry(account, auth);
          if (directCode.length > 0) {
            ECardNativeHelper.saveAndBroadcastCode(prefs, directCode);
            return {
              code: directCode,
              relogged: false,
              errorMessage: '',
              authExpired: false
            };
          }
        }
      } catch (e) {
        firstError = String(e);
        hilog.warn(DOMAIN, TAG, `Direct barcode fetch failed (${firstError}), will attempt native SSO relogin`);
      }
    }

    // 2. 直接取码失败（通常是因为主应用在墓碑后台或被杀，synjones-auth 会话已过期）
    //    使用本地持久化的统一身份认证凭据在原生侧静默重登，无需拉起 Flutter 引擎
    if (username.length > 0 && password.length > 0) {
      try {
        hilog.info(DOMAIN, TAG, 'Starting native ZJU CAS SSO relogin for ECard...');
        const creds = await ECardNativeHelper.reloginSynjones(username, password, account);
        auth = creds.synjonesAuth;
        account = creds.eCardAccount;
        try {
          prefs.putSync('synjonesAuth', auth);
          prefs.putSync('eCardAccount', account);
          prefs.flush();
        } catch (e) {}

        const freshCode = await ECardNativeHelper.requestBarcodeWithRetry(account, auth);
        if (freshCode.length > 0) {
          ECardNativeHelper.saveAndBroadcastCode(prefs, freshCode);
          hilog.info(DOMAIN, TAG, 'Native ZJU CAS SSO relogin & barcode refresh succeeded');
          return {
            code: freshCode,
            relogged: true,
            errorMessage: '',
            authExpired: false
          };
        }
      } catch (reloginErr) {
        const reloginMsg = String(reloginErr);
        hilog.error(DOMAIN, TAG, `Native ZJU CAS SSO relogin failed: ${reloginMsg}`);
        if (reloginMsg.indexOf('BAD_CREDENTIALS') >= 0) {
          return {
            code: '',
            relogged: false,
            errorMessage: '统一身份认证密码可能已变更，请打开应用重新登录。',
            authExpired: true
          };
        }
        return {
          code: '',
          relogged: false,
          errorMessage: '当前网络无法连接浙大校园卡服务，请检查网络或代理设置后重试。',
          authExpired: false
        };
      }
    }

    if (firstError.indexOf('AUTH_EXPIRED') >= 0) {
      return {
        code: '',
        relogged: false,
        errorMessage: '校园卡登录态已过期，请打开应用自动同步登录态后再试。',
        authExpired: true
      };
    }
    return {
      code: '',
      relogged: false,
      errorMessage: '当前网络环境不稳定，刷新付款码超时。请检查网络信号后重试。',
      authExpired: false
    };
  }

  private static saveAndBroadcastCode(prefs: preferences.Preferences, code: string): void {
    try {
      prefs.putSync('paymentCode', code);
      prefs.putSync('paymentCodeTime', Date.now());
      prefs.putSync('displayName', '付款码');
      prefs.putSync('hasCode', '1');
      prefs.flush();
    } catch (e) {}
    ECardNativeHelper.pushPaymentCodeToAllWidgets(prefs, code, '付款码');
  }

  /// 发起取码请求（强制 usingProxy: false 绕过系统 HTTP 代理，防止挂代理时无法访问浙大内网）
  static async requestBarcodeWithRetry(account: string, auth: string): Promise<string> {
    const url: string = `${BARCODE_URL_PREFIX}${account}${BARCODE_URL_SUFFIX}`;
    const header: Record<string, string> = {
      'synjones-auth': `bearer ${auth}`,
      'User-Agent': USER_AGENT,
      'Accept': 'application/json, text/plain, */*',
      'Connection': 'keep-alive',
      'Cache-Control': 'no-cache'
    };

    let lastErrMsg: string = '';
    for (let attempt = 1; attempt <= 2; attempt++) {
      const httpRequest: http.HttpRequest = http.createHttp();
      let redirectedToAuth = false;
      httpRequest.on('headersReceive', (hdr: Object) => {
        const loc = ECardNativeHelper.getHeaderValue(hdr, 'location');
        if (loc.length > 0 && (loc.indexOf('cas/login') >= 0 || loc.indexOf('identity.zju.edu.cn') >= 0)) {
          redirectedToAuth = true;
        }
      });

      try {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: header,
          connectTimeout: 8000,
          readTimeout: 8000,
          usingProxy: false,
          expectDataType: http.HttpDataType.STRING
        };
        const response: http.HttpResponse = await httpRequest.request(url, options);
        if (redirectedToAuth || response.responseCode === 401 || response.responseCode === 403 || response.responseCode === 901) {
          throw new Error('AUTH_EXPIRED');
        }
        if (response.responseCode === 200) {
          const text: string = (response.result as string) || '';
          const trimmed = text.trim();
          if (trimmed.indexOf('<!DOCTYPE') === 0 || trimmed.indexOf('<html') === 0 || trimmed.indexOf('cas/login') >= 0 || trimmed.indexOf('统一身份认证') >= 0) {
            throw new Error('AUTH_EXPIRED');
          }
          const payload: Record<string, Object> = JSON.parse(trimmed) as Record<string, Object>;
          const codeVal: Object = payload['code'];
          const statusVal: Object = payload['status'];
          const kickoutVal: Object = payload['kickout'];
          const msgVal: string = String(payload['msg'] || payload['message'] || '').toLowerCase();
          if (
            codeVal === 401 || codeVal === '401' ||
            codeVal === 403 || codeVal === '403' ||
            codeVal === 901 || codeVal === '901' ||
            statusVal === 401 || statusVal === '401' ||
            kickoutVal === 1 || kickoutVal === '1' ||
            msgVal.indexOf('token') >= 0 ||
            msgVal.indexOf('过期') >= 0 ||
            msgVal.indexOf('登录') >= 0 ||
            msgVal.indexOf('unauthorized') >= 0
          ) {
            throw new Error('AUTH_EXPIRED');
          }
          const data: Record<string, Object> = payload['data'] as Record<string, Object>;
          if (data !== undefined && data !== null) {
            if (data['kickout'] === 1 || data['kickout'] === '1') {
              throw new Error('AUTH_EXPIRED');
            }
            const barcodes: string[] = data['barcode'] as string[];
            if (barcodes !== undefined && barcodes !== null && barcodes.length > 0) {
              const rawCode: string = String(barcodes[0] || '');
              if (ECardNativeHelper.isValidBarcode(rawCode)) {
                return rawCode;
              } else {
                // 降级假码（如鉴权失效时返回的非标短字符串）按过期处理以触发重登
                throw new Error('AUTH_EXPIRED');
              }
            }
          }
          // 200 响应但无有效 barcode，通常也是会话失效
          throw new Error('AUTH_EXPIRED');
        } else {
          lastErrMsg = `HTTP ${response.responseCode}`;
        }
      } catch (err) {
        const errStr: string = String(err);
        if (errStr.indexOf('AUTH_EXPIRED') >= 0) {
          throw new Error('AUTH_EXPIRED');
        }
        lastErrMsg = errStr;
        hilog.warn(DOMAIN, TAG, `requestBarcode attempt ${attempt} failed: ${errStr}`);
      } finally {
        httpRequest.destroy();
      }

      if (attempt < 2) {
        await new Promise<void>((resolve) => setTimeout(resolve, 300));
      }
    }

    throw new Error(lastErrMsg.length > 0 ? lastErrMsg : 'NETWORK_TIMEOUT');
  }

  private static isValidBarcode(s: string): boolean {
    if (s.length < 14 || s.length > 64) {
      return false;
    }
    return /^[A-Za-z0-9+/=_\-]+$/.test(s);
  }

  /// 获取校园卡账号（选择余额最高的主卡）
  static async fetchCampusCardAccount(synjonesAuth: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const cardHeader: Record<string, string> = {
        'Synjones-Auth': `Bearer ${synjonesAuth}`,
        'User-Agent': USER_AGENT,
        'Accept': 'application/json, text/plain, */*'
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: cardHeader,
        connectTimeout: 8000,
        readTimeout: 8000,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      };
      const response = await httpRequest.request(CAMPUS_CARDS_URL, options);
      if (response.responseCode !== 200) {
        throw new Error(`getCampusCards HTTP ${response.responseCode}`);
      }
      const text = (response.result as string) || '';
      const payload = JSON.parse(text) as Record<string, Object>;
      const data = payload['data'] as Record<string, Object>;
      if (!data) {
        throw new Error('getCampusCards empty data');
      }
      const cardList = data['card'] as Array<Record<string, Object>>;
      if (!cardList || cardList.length === 0) {
        throw new Error('getCampusCards empty card list');
      }
      let bestAccount = '';
      let bestBalance = -1e18;
      for (let i = 0; i < cardList.length; i++) {
        const card = cardList[i];
        const acc = String(card['account'] || '');
        const bal = Number(card['db_balance'] || 0);
        if (acc.length > 0 && bal >= bestBalance) {
          bestBalance = bal;
          bestAccount = acc;
        }
      }
      return bestAccount;
    } finally {
      httpRequest.destroy();
    }
  }

  /// 原生侧完整执行 ZJU CAS 统一身份认证 -> 换取校园卡 synjones-auth 与 account
  private static async reloginSynjones(
    username: string,
    password: string,
    existingAccount: string
  ): Promise<ReloginCredentials> {
    const cookieMap = new Map<string, string>();

    // Step 1: GET CAS login page -> 获取 execution 与初始会话 Cookie
    const loginPageResp = await ECardNativeHelper.requestWithTrace(
      CAS_LOGIN_URL,
      http.RequestMethod.GET,
      cookieMap,
      '',
      false
    );
    const execMatch = loginPageResp.body.match(/name="execution"\s+value="([^"]+)"/);
    if (execMatch === null || execMatch.length < 2) {
      throw new Error('CAS_EXECUTION_MISSING');
    }
    const execution = execMatch[1];

    // Step 2: GET RSA public key
    const pubKeyResp = await ECardNativeHelper.requestWithTrace(
      CAS_PUBKEY_URL,
      http.RequestMethod.GET,
      cookieMap,
      '',
      false
    );
    const pubKeyJson = JSON.parse(pubKeyResp.body) as Record<string, Object>;
    const modulus = String(pubKeyJson['modulus'] || '');
    const exponent = String(pubKeyJson['exponent'] || '');
    if (modulus.length === 0 || exponent.length === 0) {
      throw new Error('CAS_PUBKEY_MISSING');
    }

    // Step 3: RSA 加密密码（纯 ArkTS 字节数组模幂运算，兼容所有长度密码）
    const pwdHex = ECardNativeHelper.utf8ToHex(password);
    const pwdEnc = ECardNativeHelper.rsaModPowHex(pwdHex, exponent, modulus).padStart(128, '0');

    // Step 4: POST CAS login 表单，获取 iPlanetDirectoryPro
    const formBody =
      `username=${encodeURIComponent(username)}` +
      `&password=${encodeURIComponent(pwdEnc)}` +
      `&execution=${encodeURIComponent(execution)}` +
      `&_eventId=submit&rememberMe=true`;
    await ECardNativeHelper.requestWithTrace(
      CAS_LOGIN_URL,
      http.RequestMethod.POST,
      cookieMap,
      formBody,
      true
    );

    const ssoCookie = cookieMap.get('iPlanetDirectoryPro') || '';
    if (ssoCookie.length === 0) {
      throw new Error('BAD_CREDENTIALS');
    }

    // Step 5: 访问 elife OAuth2 入口并沿重定向链提取 synjones-auth
    let synjonesAuth = '';
    let currentUrl = ELIFE_OAUTH_URL;
    for (let hop = 0; hop < 10; hop++) {
      const hopResp = await ECardNativeHelper.requestSingleRedirectHop(currentUrl, cookieMap);
      if (hopResp.synjonesAuth.length > 0) {
        synjonesAuth = hopResp.synjonesAuth;
        break;
      }
      if (hopResp.locations.length === 0) {
        break;
      }
      const nextLoc = hopResp.locations[0];
      const match = nextLoc.match(/synjones-auth=([^&]+)/);
      if (match !== null && match.length >= 2) {
        synjonesAuth = match[1];
        break;
      }
      currentUrl = ECardNativeHelper.resolveRedirectUrl(currentUrl, nextLoc);
    }

    if (synjonesAuth.length === 0) {
      throw new Error('SYNJONES_AUTH_MISSING');
    }

    let account = existingAccount;
    if (account.length === 0) {
      account = await ECardNativeHelper.fetchCampusCardAccount(synjonesAuth);
    }
    if (account.length === 0) {
      throw new Error('ECARD_ACCOUNT_MISSING');
    }

    return {
      synjonesAuth: synjonesAuth,
      eCardAccount: account
    };
  }

  /// 发起请求并收集所有响应头中的 Set-Cookie 与 Location
  private static async requestWithTrace(
    url: string,
    method: http.RequestMethod,
    cookieMap: Map<string, string>,
    formBody: string,
    stopOnFirstRedirect: boolean
  ): Promise<SingleHopResponse> {
    const httpRequest = http.createHttp();
    const locations: string[] = [];
    let foundSynjonesAuth = '';
    let resolvedEarly = false;

    const header: Record<string, string> = {
      'User-Agent': USER_AGENT,
      'Accept': 'text/html,application/xhtml+xml,application/json,*/*'
    };
    const cookieHeader = ECardNativeHelper.buildCookieHeader(cookieMap);
    if (cookieHeader.length > 0) {
      header['Cookie'] = cookieHeader;
    }
    if (method === http.RequestMethod.POST) {
      header['Content-Type'] = 'application/x-www-form-urlencoded; charset=utf-8';
    }

    return await new Promise<SingleHopResponse>((resolve, reject) => {
      httpRequest.on('headersReceive', (hdr: Object) => {
        ECardNativeHelper.collectCookies(hdr, cookieMap);
        const loc = ECardNativeHelper.getHeaderValue(hdr, 'location');
        if (loc.length > 0) {
          locations.push(loc);
          const match = loc.match(/synjones-auth=([^&]+)/);
          if (match !== null && match.length >= 2) {
            foundSynjonesAuth = match[1];
          }
          if (stopOnFirstRedirect || foundSynjonesAuth.length > 0) {
            if (!resolvedEarly) {
              resolvedEarly = true;
              resolve({
                statusCode: 302,
                body: '',
                locations: locations,
                synjonesAuth: foundSynjonesAuth
              });
              try {
                httpRequest.destroy();
              } catch (e) {}
            }
          }
        }
      });

      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        connectTimeout: 8000,
        readTimeout: 8000,
        usingProxy: false,
        expectDataType: http.HttpDataType.STRING
      };
      if (method === http.RequestMethod.POST && formBody.length > 0) {
        options.extraData = formBody;
      }

      httpRequest.request(url, options).then((response: http.HttpResponse) => {
        if (resolvedEarly) {
          return;
        }
        if (response.header) {
          ECardNativeHelper.collectCookies(response.header, cookieMap);
          const loc = ECardNativeHelper.getHeaderValue(response.header, 'location');
          if (loc.length > 0 && !locations.includes(loc)) {
            locations.push(loc);
            const match = loc.match(/synjones-auth=([^&]+)/);
            if (match !== null && match.length >= 2) {
              foundSynjonesAuth = match[1];
            }
          }
        }
        const text = (response.result as string) || '';
        try {
          httpRequest.destroy();
        } catch (e) {}
        resolve({
          statusCode: response.responseCode,
          body: text,
          locations: locations,
          synjonesAuth: foundSynjonesAuth
        });
      }).catch((err: BusinessError) => {
        if (resolvedEarly) {
          return;
        }
        try {
          httpRequest.destroy();
        } catch (e) {}
        if (foundSynjonesAuth.length > 0 || (stopOnFirstRedirect && locations.length > 0)) {
          resolve({
            statusCode: 302,
            body: '',
            locations: locations,
            synjonesAuth: foundSynjonesAuth
          });
        } else {
          reject(new Error(`HTTP request failed: ${err.code} ${err.message}`));
        }
      });
    });
  }

  /// 单跳重定向请求：收到首个 Location 立即中止自动跟跳，确保跨域 Cookie（如 iPlanetDirectoryPro）每跳完整携带
  private static async requestSingleRedirectHop(
    url: string,
    cookieMap: Map<string, string>
  ): Promise<SingleHopResponse> {
    return await ECardNativeHelper.requestWithTrace(
      url,
      http.RequestMethod.GET,
      cookieMap,
      '',
      true
    );
  }

  private static getHeaderValue(hdr: Object, targetKeyLower: string): string {
    try {
      const rec = hdr as Record<string, Object>;
      const keys = Object.keys(rec);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        if (k.toLowerCase() === targetKeyLower) {
          const val = rec[k];
          if (typeof val === 'string') {
            return val;
          }
          if (Array.isArray(val) && val.length > 0) {
            return String(val[0]);
          }
        }
      }
    } catch (e) {}
    return '';
  }

  private static collectCookies(hdr: Object, cookieMap: Map<string, string>): void {
    try {
      const rec = hdr as Record<string, Object>;
      const keys = Object.keys(rec);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        if (k.toLowerCase() === 'set-cookie') {
          const val = rec[k];
          if (typeof val === 'string') {
            ECardNativeHelper.parseSetCookieString(val, cookieMap);
          } else if (Array.isArray(val)) {
            const arr = val as Array<Object>;
            for (let j = 0; j < arr.length; j++) {
              ECardNativeHelper.parseSetCookieString(String(arr[j]), cookieMap);
            }
          }
        }
      }
    } catch (e) {}
  }

  private static parseSetCookieString(raw: string, cookieMap: Map<string, string>): void {
    const lines = raw.split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      const firstSemi = line.indexOf(';');
      const pair = firstSemi >= 0 ? line.substring(0, firstSemi) : line;
      const eqIdx = pair.indexOf('=');
      if (eqIdx > 0) {
        const name = pair.substring(0, eqIdx).trim();
        const value = pair.substring(eqIdx + 1).trim();
        // 忽略被服务端置空删除的 Cookie（如 Max-Age=0 或空值）
        if (value.length > 0 && line.toLowerCase().indexOf('max-age=0') < 0) {
          cookieMap.set(name, value);
        }
      }
    }
  }

  private static buildCookieHeader(cookieMap: Map<string, string>): string {
    const parts: string[] = [];
    cookieMap.forEach((value: string, key: string) => {
      parts.push(`${key}=${value}`);
    });
    return parts.join('; ');
  }

  private static resolveRedirectUrl(baseUrl: string, location: string): string {
    if (location.indexOf('http://') === 0 || location.indexOf('https://') === 0) {
      return location;
    }
    const schemeEnd = baseUrl.indexOf('://');
    if (schemeEnd < 0) {
      return location;
    }
    const hostStart = schemeEnd + 3;
    const pathStart = baseUrl.indexOf('/', hostStart);
    const origin = pathStart >= 0 ? baseUrl.substring(0, pathStart) : baseUrl;
    if (location.indexOf('/') === 0) {
      return `${origin}${location}`;
    }
    const lastSlash = baseUrl.lastIndexOf('/');
    const baseDir = lastSlash >= hostStart ? baseUrl.substring(0, lastSlash + 1) : `${origin}/`;
    return `${baseDir}${location}`;
  }

  private static utf8ToHex(str: string): string {
    const encoded = encodeURIComponent(str);
    const bytes: number[] = [];
    for (let i = 0; i < encoded.length; i++) {
      if (encoded[i] === '%' && i + 2 < encoded.length) {
        const hexByte = parseInt(encoded.substring(i + 1, i + 3), 16);
        bytes.push(isNaN(hexByte) ? 0 : hexByte);
        i += 2;
      } else {
        bytes.push(encoded.charCodeAt(i) & 0xff);
      }
    }
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      hex += bytes[i].toString(16);
    }
    return hex;
  }

  // ==================== Pure ArkTS Big-Integer Modular Exponentiation ====================

  private static hexToBytesLE(hexStr: string): number[] {
    let clean = hexStr.trim();
    if (clean.length % 2 !== 0) {
      clean = '0' + clean;
    }
    const out: number[] = [];
    for (let i = clean.length - 2; i >= 0; i -= 2) {
      const byteVal = parseInt(clean.substring(i, i + 2), 16);
      out.push(isNaN(byteVal) ? 0 : byteVal);
    }
    return ECardNativeHelper.trimBytesLE(out);
  }

  private static trimBytesLE(a: number[]): number[] {
    let end = a.length;
    while (end > 0 && a[end - 1] === 0) {
      end--;
    }
    return end === a.length ? a : a.slice(0, end);
  }

  private static cmpBytesLE(a: number[], b: number[]): number {
    if (a.length !== b.length) {
      return a.length > b.length ? 1 : -1;
    }
    for (let i = a.length - 1; i >= 0; i--) {
      if (a[i] !== b[i]) {
        return a[i] > b[i] ? 1 : -1;
      }
    }
    return 0;
  }

  private static subBytesLE(a: number[], b: number[]): number[] {
    const res: number[] = [];
    let borrow = 0;
    for (let i = 0; i < a.length; i++) {
      const bi = i < b.length ? b[i] : 0;
      let diff = a[i] - bi - borrow;
      if (diff < 0) {
        diff += 256;
        borrow = 1;
      } else {
        borrow = 0;
      }
      res.push(diff);
    }
    return ECardNativeHelper.trimBytesLE(res);
  }

  private static addModLE(a: number[], b: number[], mod: number[]): number[] {
    const maxLen = a.length > b.length ? a.length : b.length;
    const sum: number[] = [];
    let carry = 0;
    for (let i = 0; i < maxLen; i++) {
      const ai = i < a.length ? a[i] : 0;
      const bi = i < b.length ? b[i] : 0;
      const s = ai + bi + carry;
      sum.push(s & 0xff);
      carry = s >> 8;
    }
    if (carry > 0) {
      sum.push(carry);
    }
    let trimmed = ECardNativeHelper.trimBytesLE(sum);
    if (ECardNativeHelper.cmpBytesLE(trimmed, mod) >= 0) {
      trimmed = ECardNativeHelper.subBytesLE(trimmed, mod);
    }
    return trimmed;
  }

  private static mulModLE(a: number[], b: number[], mod: number[]): number[] {
    let res: number[] = [];
    for (let i = a.length - 1; i >= 0; i--) {
      const byteVal = a[i];
      for (let bit = 7; bit >= 0; bit--) {
        res = ECardNativeHelper.addModLE(res, res, mod);
        if (((byteVal >> bit) & 1) === 1) {
          res = ECardNativeHelper.addModLE(res, b, mod);
        }
      }
    }
    return res;
  }

  private static rsaModPowHex(baseHex: string, expHex: string, modHex: string): string {
    const mod = ECardNativeHelper.hexToBytesLE(modHex);
    if (mod.length === 0) {
      return '';
    }
    let base = ECardNativeHelper.hexToBytesLE(baseHex);
    while (ECardNativeHelper.cmpBytesLE(base, mod) >= 0) {
      base = ECardNativeHelper.subBytesLE(base, mod);
    }
    const exp = ECardNativeHelper.hexToBytesLE(expHex);
    let acc: number[] = [1];
    for (let i = exp.length - 1; i >= 0; i--) {
      const byteVal = exp[i];
      for (let bit = 7; bit >= 0; bit--) {
        acc = ECardNativeHelper.mulModLE(acc, acc, mod);
        if (((byteVal >> bit) & 1) === 1) {
          acc = ECardNativeHelper.mulModLE(acc, base, mod);
        }
      }
    }
    if (acc.length === 0) {
      return '0';
    }
    let hexOut = '';
    for (let i = acc.length - 1; i >= 0; i--) {
      const h = acc[i].toString(16);
      if (i < acc.length - 1 && h.length < 2) {
        hexOut += '0' + h;
      } else {
        hexOut += h;
      }
    }
    return hexOut;
  }

  // ==================== Hive Fallback Credential Reader ====================

  /// 从应用沙箱内的 celechron_secure_store.hive 文件兜底提取 [username, password, synjonesAuth, eCardAccount]
  private static tryExtractCredentialsFromHive(context: common.Context): string[] {
    const result: string[] = ['', '', '', ''];
    const filesDir = context.filesDir;
    const candidates: string[] = [
      `${filesDir}/app_flutter/celechron_secure_store.hive`,
      `${filesDir}/celechron_secure_store.hive`
    ];
    for (let c = 0; c < candidates.length; c++) {
      const path = candidates[c];
      try {
        if (!fileIo.accessSync(path)) {
          continue;
        }
        const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
        try {
          const stat = fileIo.statSync(file.fd);
          if (stat.size <= 0 || stat.size > 2 * 1024 * 1024) {
            continue;
          }
          const buf = new ArrayBuffer(stat.size);
          fileIo.readSync(file.fd, buf);
          const bytes = new Uint8Array(buf);
          result[0] = ECardNativeHelper.findLastHiveStringValue(bytes, 'username');
          result[1] = ECardNativeHelper.findLastHiveStringValue(bytes, 'password');
          result[2] = ECardNativeHelper.findLastHiveStringValue(bytes, 'synjonesAuth');
          result[3] = ECardNativeHelper.findLastHiveStringValue(bytes, 'eCardAccount');
          if (result[0].length > 0 && result[1].length > 0) {
            break;
          }
        } finally {
          fileIo.closeSync(file);
        }
      } catch (e) {
        // ignore
      }
    }
    return result;
  }

  private static findLastHiveStringValue(bytes: Uint8Array, key: string): string {
    const keyLen = key.length;
    let found = '';
    const decoder = util.TextDecoder.create('utf-8');
    for (let i = 0; i + 2 + keyLen + 5 <= bytes.length; i++) {
      // Hive ASCII key header: [0x01, keyLen, ...keyBytes]
      if (bytes[i] === 1 && bytes[i + 1] === keyLen) {
        let match = true;
        for (let k = 0; k < keyLen; k++) {
          if (bytes[i + 2 + k] !== key.charCodeAt(k)) {
            match = false;
            break;
          }
        }
        if (match) {
          const valStart = i + 2 + keyLen;
          // Hive String value type is 4, followed by 4-byte LE byte length
          if (bytes[valStart] === 4) {
            const strLen =
              bytes[valStart + 1] |
              (bytes[valStart + 2] << 8) |
              (bytes[valStart + 3] << 16) |
              (bytes[valStart + 4] << 24);
            const payloadStart = valStart + 5;
            if (strLen > 0 && strLen <= 512 && payloadStart + strLen <= bytes.length) {
              const sub = bytes.subarray(payloadStart, payloadStart + strLen);
              found = decoder.decodeToString(sub);
            }
          }
        }
      }
    }
    return found;
  }
}
