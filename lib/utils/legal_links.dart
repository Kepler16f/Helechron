/// 应用内法律文档入口。
///
/// 商店审核要求提供可公开访问的隐私政策地址；应用内同时保留离线文本，
/// 避免网络不可达时无法查看。发布时可通过
/// `--dart-define=PRIVACY_POLICY_URL=...` 覆盖为已备案域名下的地址。
const String privacyPolicyUrl = String.fromEnvironment(
  'PRIVACY_POLICY_URL',
  defaultValue: 'https://kepler16f.github.io/Helechron/privacy.html',
);

const String userAgreementUrl = String.fromEnvironment(
  'USER_AGREEMENT_URL',
  defaultValue: 'https://kepler16f.github.io/Helechron/terms.html',
);

/// 隐私政策版本号。修改隐私政策内容时必须递增，以便重新征得同意。
const int privacyPolicyVersion = 1;

/// 工信部 APP 备案号。拿到备案号后可通过
/// `--dart-define=ICP_FILING_NUMBER=浙ICP备...` 注入，或在设置页展示。
const String icpFilingNumber = String.fromEnvironment(
  'ICP_FILING_NUMBER',
  defaultValue: '',
);
