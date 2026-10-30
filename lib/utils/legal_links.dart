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
const int privacyPolicyVersion = 3;

/// 所有面向用户的入口共用的项目来源与身份说明。
const String appOriginStatement = 'Helechron 是基于 Celechron 开源项目移植并扩展功能的非官方版本，'
    '由 $developerName（$developerSubjectType）负责移植适配、独立开发新增功能及后续维护与发布。'
    '本应用不是 Celechron 官方应用，不代表 Celechron 原项目或其维护团队，'
    '也不是浙江大学官方应用。';

const String projectUrl = 'https://github.com/Kepler16f/Helechron';
const String releasesUrl = '$projectUrl/releases';

/// 开发者（个人信息处理者）名称。
///
/// 上架审核会核对「应用内用户协议展示的名称」与「AppGallery Connect 开发者信息」
/// 是否一致，不一致会直接驳回。个人主体填实名姓名，企业主体填营业执照全称，
/// 必须与 AGC 逐字相同。
///
/// 发布时通过 `--dart-define=DEVELOPER_NAME=...` 覆盖；默认值与
/// `tool/store/legal_identity.py` 保持一致（由 `tool/store/check_release.py` 校验）。
const String developerName = String.fromEnvironment(
  'DEVELOPER_NAME',
  defaultValue: '胡天泽',
);

/// 开发者主体类型。个人主体填“个人开发者”，企业主体填“企业”。
const String developerSubjectType = String.fromEnvironment(
  'DEVELOPER_SUBJECT_TYPE',
  defaultValue: '个人开发者',
);

/// 工信部 APP 备案号。
///
/// 备案号是上架硬性门槛，拿到后通过 `--dart-define=ICP_FILING_NUMBER=...` 注入，
/// 应用内「关于」页会展示；未注入时显示占位文本提醒发布者补齐。
const String icpFilingNumber = String.fromEnvironment(
  'ICP_FILING_NUMBER',
  defaultValue: '【ICP备案号待补充】',
);

/// 协议文本中的占位符。
///
/// `assets/legal/*.txt` 与在线版 `docs/*.html` 共用同一套占位符，渲染时替换为
/// 上面的常量，保证应用内文本与商店在线文本一致。
const Map<String, String> legalPlaceholders = <String, String>{
  '{{DEVELOPER_NAME}}': developerName,
  '{{DEVELOPER_SUBJECT_TYPE}}': developerSubjectType,
  '{{ICP_FILING_NUMBER}}': icpFilingNumber,
};
