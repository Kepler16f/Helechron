# Helechron 华为应用市场（AppGallery）上架手册

> 适用版本：`0.1.7`（versionCode `100`）
> 最后更新：2026-10-26
> 备案细节另见：[docs/APP备案指南.md](../../docs/APP备案指南.md)

## 0. 先说结论

代码和构建侧已经准备好，剩下的是**账号、资质和人工材料**：

1. 华为开发者账号实名认证
2. 工信部 APP 备案（最长前置，建议今天就开始）
3. 软件著作权 / 电子版权认证（审核可能要求）
4. AGC 发布证书 + Profile（鸿蒙）或 Android keystore
5. 可用测试账号、应用截图、商店文案
6. 第三方商标风险处理（当前图标已替换为原创图标）

HarmonyOS 版和 Android 版在 AGC 中是**两个独立应用记录**，包名不同，需要分别提交。首次上架建议先走 HarmonyOS 版。

## 1. 当前完成度

| 项目 | 状态 | 位置 |
|---|---|---|
| 版本号统一为 0.1.7 / 100 | ✅ | `pubspec.yaml`、`tool/pubspec_ohos.yaml`、`ohos/AppScope/app.json5`、`lib/worker/fuse.dart` |
| 首次启动隐私同意门 | ✅ | `lib/page/consent_page.dart`、`lib/services/consent_store.dart`、`lib/main.dart`；空白复选框默认未勾选，未勾选时「同意并继续」置灰不可点，底部常驻「不同意并退出应用」 |
| 应用内隐私政策 / 用户协议 | ✅ | `assets/legal/*.txt`、`lib/page/legal_page.dart`；`{{DEVELOPER_NAME}}`、`{{DEVELOPER_SUBJECT_TYPE}}`、`{{ICP_FILING_NUMBER}}` 占位符由 `lib/utils/legal_links.dart` 渲染时替换 |
| 在线隐私政策 / 用户协议 | ✅ | `docs/privacy.html`、`docs/terms.html`（需部署） |
| 设置页隐私入口 | ✅ | 设置 → 关于 → 隐私政策 / 用户协议 |
| Android release 签名 | ✅ | `android/app/build.gradle.kts`、`android/key.properties.example` |
| HarmonyOS 发布签名 | ✅ | `tool/ohos/apply_signing.py` |
| 签名发布 CI | ✅ | `.github/workflows/release-appgallery.yml` |
| 商店图标（K 手绘笔记本） | ✅ | `store/appgallery/icon/`（已应用到各平台）；包内单层图标 1024×1024 |
| 开发者名称统一（个人开发者） | ✅ | `lib/utils/legal_links.dart`（`developerName` / `developerSubjectType`） |
| APP 备案 | ⏳ 待你完成 | 见 `docs/APP备案指南.md` |
| APP 备案号展示 | ⏳ 待完成 | 应用内目前显示占位符 `【ICP备案号待补充】`；拿到备案号后用 `--dart-define=ICP_FILING_NUMBER=...` 重新构建 |
| 软著 / 电子版权 | ⏳ 待你完成 | 中国版权保护中心或华为合作渠道 |
| AGC 证书 / Profile | ⏳ 待你完成 | 见第 4 节 |
| 测试账号 | ⏳ 待你完成 | 见第 3.4 节 |
| 应用截图 | ⏳ 待你完成 | 见第 7 节 |

## 2. 最快路径

| 时间 | 动作 |
|---|---|
| 今天 | 华为开发者联盟实名认证；确定个人/企业主体；确认 `celechron.top` 归属；开始软著/电子版权申请 |
| 今天 | 在 AGC 创建 HarmonyOS 应用，包名 `top.celechron.helechron` |
| 今天 | 生成鸿蒙发布证书、Profile、`.p12`；配置 GitHub Secrets |
| 1–2 天内 | 跑通 `Release to AppGallery`，拿到签名 `.app` 和 `.apk` |
| 并行 | 准备测试账号、截图、商店文案；部署隐私政策页面 |
| 1–20 个工作日 | 等 APP 备案（法定最长 20 个工作日，通常 1–2 周） |
| 备案号到手 | 回填 AGC + 应用内展示；提交上架审核 |
| 1–3 个工作日 | 审核、按意见修改、发布 |

## 3. 硬性前置

### 3.1 华为开发者账号

- 入口：<https://developer.huawei.com/consumer/cn/>
- 个人主体：身份证 + 人脸核验，通常当日通过。
- 企业主体：营业执照、法人认证、授权书等。
- **备案主体、软著主体、开发者账号主体三者必须一致**，否则审核会被卡。
- 个人主体可以发布免费、无广告、无内购的工具类应用；不要勾选游戏、金融、医疗等受限类目。

### 3.2 APP 备案（最长前置）

- 2023 年起，境内分发、上架的 APP 必须完成工信部 APP 备案；应用商店会校验备案号。
- 备案通过接入服务商提交：鸿蒙端可在 AGC 的 “ICP 备案” 服务中走；其他安卓渠道在各自后台登记同一个备案号。
- 个人可备案，但需要提供主体信息、APP 信息、接入信息；通常需要一个已完成 ICP 备案的域名作为接入域名。
- Helechron 没有自建后端，但 `api.celechron.top` / `calendar.celechron.top` 不属于你运营，不要把它们填成你的接入域名；按“无自建服务”如实填写，具体以接入商表单为准。
- 详细草稿、表单字段和时间线见 [docs/APP备案指南.md](../../docs/APP备案指南.md)。
- 拿到备案号后：
  1. 回填 AGC 应用信息；
  2. 用 `--dart-define=ICP_FILING_NUMBER=...` 重新构建，设置页会显示备案号（`lib/utils/legal_links.dart` 已支持）；
  3. 用 `--dart-define=DEVELOPER_NAME=...` 确认应用内展示的开发者名称与 AGC「开发者信息」完全一致（默认 `胡天泽`，个人开发者）；不一致会被以「用户协议展示的公司名称与开发者信息不一致」驳回。

### 3.3 软件著作权 / 电子版权

- 华为审核对普通工具类不一定强制，但涉及“浙江大学”相关场景、校园卡功能时，**建议提前准备**。
- 中国版权保护中心正常登记免费，排队约 2 个月；电子版权认证（华为合作渠道等）几百元，1–5 个工作日，上架通常认可。
- 本项目是 GPL-3.0 开源代码的分支：
  - 保留 `LICENSE`、应用内“开源许可证”页和上游 Celechron 的署名；
  - 软著/电子版权申请主体应与备案主体一致；
  - 如审核质疑权属，准备源码仓库地址、LICENSE、上游项目地址和你的修改说明。

### 3.4 测试账号（非常关键）

Helechron 的核心功能依赖浙江大学统一身份认证。审核员没有浙大账号，**不提供测试账号极可能被判“核心功能无法验证”**。

准备一个专用测试账号，并在 AGC “审核信息/备注”中提供：

- 账号（学号/工号）
- 密码
- 是否有短信/二次验证；如有，提供可接收验证码的方式
- 登录路径：启动 → 同意隐私政策 → 设置 → 登录
- 核心功能路径：首页“接下来”、日历、任务、学业
- 账号有效期：至少覆盖首次审核；后续版本审核仍会用到，建议长期保留

注意事项：

- 不要把个人主账号密码交给审核；用专用测试账号。
- 测试账号能看到的信息越少越好，避免真实成绩/隐私。
- 如果学校系统需要校园网/VPN，提前在审核备注中说明；审核员无法访问时，可能需要增加“演示模式”（当前未实现）。

### 3.5 名称、图标与商标

- 原图标包含“浙江大学 / ZHEJIANG UNIVERSITY / 求是”校徽元素，属于第三方商标/校名风险，AppGallery 可能要求授权书。
- 本仓库已将应用图标替换为不带学校元素的原创图标，最终选用 **K 手绘笔记本**：
  - `store/appgallery/icon/helechron_icon_1024.png`
  - `store/appgallery/icon/helechron_icon_512.png`
  - `store/appgallery/icon/helechron_icon_216.png`
  - `store/appgallery/icon/helechron_banner_1080x450.png`
- 如需重新选图，可在 `store/appgallery/icon/options2/` 查看方案，选中后用
  `python tool/store/export_store_icon.py <icon.png>` 导出，再运行
  `python tool/store/apply_store_icon.py` 应用到各平台。
- 应用名称统一为 **Helechron**；Android `android:label` 已从 `Aelechron` 改为 `Helechron`。
- 应用介绍中保留“非浙江大学官方应用，与浙江大学无隶属或合作关系”的声明；不要在名称/图标/宣传图里使用校名、校徽。
- 校园卡付款码属于敏感功能：审核备注中说明“仅展示用户本人已登录账户的付款码，不提供支付、清算、资金托管服务”。如首次审核被重点问询，可临时隐藏入口后再提交。

## 4. 签名

### 4.0 创建应用前先确认包名

- HarmonyOS 包名：`top.celechron.helechron`
- Android 包名：`top.celechron.aelechron`
- AGC 创建应用时会校验包名是否已被占用；如果已被占用，只能在**首次发布前**改包名：
  - 鸿蒙：`ohos/AppScope/app.json5` 的 `bundleName`
  - Android：`android/app/build.gradle.kts` 的 `applicationId`
- 包名一旦发布就不可修改，改包名等于新应用，老用户无法升级。

### 4.1 HarmonyOS 发布证书 + Profile

1. 用 DevEco Studio 生成密钥和 CSR：
   - `Build` → `Generate Key and CSR`
   - Key store file：`release.p12`
   - Alias：`helechron`（自己记住）
   - Password：强密码，保存到密码管理器
   - Key algorithm：按 DevEco 默认（ECC）即可
   - CSR file：`release.csr`
2. AGC → 用户与访问 → 证书管理：
   - 新增证书 → 选择“发布证书” → 上传 `release.csr` → 下载 `release.cer`
3. AGC → Profile → 新增：
   - 类型：发布（Release）
   - 选择应用：`top.celechron.helechron`
   - 绑定刚创建的证书
   - 下载 `release.p7b`
4. 三个文件放在 `ohos/signature/`（已被 `.gitignore` 忽略）：
   - `release.p12`
   - `release.cer`
   - `release.p7b`
5. 本地构建也可以在 DevEco 中配置：
   - `File` → `Project Structure` → `Signing Configs`
   - 选择 release 证书/Profile/keystore
   - `Build` → `Build App(s)` 生成签名 `.app`

> 有效期：发布证书通常 3 年，Profile 通常 1 年；到期前必须续期，否则无法发布新版本。建议现在就建日历提醒。

> CI 签名密码：`tool/ohos/apply_signing.py` 写入的是明文密码。DevEco 图形界面保存的
> `0000001B...` 形式是它本机加密后的值，不能直接复制到 CI。若 hvigor 报密码/解密错误，
> 先在本地用 DevEco 确认证书、Profile、alias、密码能正常打包，再把这些值原样写入
> GitHub Secrets；仍失败时改用 DevEco `Build App(s)` 产出 `.app` 后手动上传。

### 4.2 Android keystore

```bash
keytool -genkeypair -v \
  -storetype PKCS12 \
  -keystore android/app/release.keystore \
  -alias helechron \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Helechron, OU=Helechron, O=Helechron, L=Hangzhou, ST=Zhejiang, C=CN"
```

- 按提示输入 keystore 密码和 key 密码；不要把密码写进 shell 历史。
- `-validity 10000` 约 27 年，满足应用市场对签名证书有效期的要求。
- keystore 和密码必须备份；丢失后无法更新已发布应用（除非使用华为应用签名服务托管）。
- 本地 `android/key.properties`：

```properties
storePassword=你的强密码
keyPassword=你的强密码
keyAlias=helechron
storeFile=app/release.keystore
```

- 该文件已被 `.gitignore` 忽略，**不要提交**。

### 4.3 华为应用签名服务（可选）

AGC 支持“应用签名”服务，由华为托管发布密钥并重新签名。使用后：

- 上传包与最终分发包的签名可能不同；
- 后续升级必须使用同一套上传密钥/签名配置；
- 具体以 AGC 上传页提示为准。

首次上架可以先用自有 keystore 直签 APK；如果后续要启用华为应用签名，按 AGC 指引迁移。

## 5. GitHub Secrets 与变量

### 5.1 Secrets

| Secret 名称 | 内容 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `release.keystore` 的 base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | `helechron` |
| `ANDROID_KEY_PASSWORD` | key 密码 |
| `OHOS_STORE_FILE_BASE64` | `release.p12` 的 base64 |
| `OHOS_STORE_FILE_PASSWORD` | `.p12` 密码 |
| `OHOS_KEY_ALIAS` | `helechron` |
| `OHOS_KEY_PASSWORD` | key 密码 |
| `OHOS_CERT_BASE64` | `release.cer` 的 base64 |
| `OHOS_PROFILE_BASE64` | `release.p7b` 的 base64 |

生成 base64：

```bash
# Linux / Git Bash
base64 -w0 android/app/release.keystore
base64 -w0 ohos/signature/release.p12
base64 -w0 ohos/signature/release.cer
base64 -w0 ohos/signature/release.p7b
```

```powershell
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/release.keystore"))
```

用 `gh` 写入（可选）：

```bash
gh secret set ANDROID_KEYSTORE_BASE64 --body "$(base64 -w0 android/app/release.keystore)"
gh secret set ANDROID_KEYSTORE_PASSWORD --body "你的密码"
gh secret set ANDROID_KEY_ALIAS --body "helechron"
gh secret set ANDROID_KEY_PASSWORD --body "你的密码"
gh secret set OHOS_STORE_FILE_BASE64 --body "$(base64 -w0 ohos/signature/release.p12)"
gh secret set OHOS_STORE_FILE_PASSWORD --body "你的密码"
gh secret set OHOS_KEY_ALIAS --body "helechron"
gh secret set OHOS_KEY_PASSWORD --body "你的密码"
gh secret set OHOS_CERT_BASE64 --body "$(base64 -w0 ohos/signature/release.cer)"
gh secret set OHOS_PROFILE_BASE64 --body "$(base64 -w0 ohos/signature/release.p7b)"
```

### 5.2 Repository variables

| Variable | 示例 | 用途 |
|---|---|---|
| `PRIVACY_POLICY_URL` | `https://你的已备案域名/privacy.html` | 构建时注入隐私政策地址 |
| `USER_AGREEMENT_URL` | `https://你的已备案域名/terms.html` | 构建时注入用户协议地址 |
| `DEVELOPER_NAME` | `胡天泽` | 构建时注入应用内展示的开发者名称，**必须与 AGC「开发者信息」中的名称完全一致**，否则会被以「用户协议展示的公司名称与开发者信息不一致」驳回 |
| `DEVELOPER_SUBJECT_TYPE` | `个人开发者` | 可选：主体类型，个人主体填「个人开发者」，企业主体填「企业」 |
| `ICP_FILING_NUMBER` | `浙ICP备XXXXXXXX号-XA` | 设置页展示备案号；**未设置时应用内显示 `【ICP备案号待补充】` 占位符，上架前必须填** |
| `CALENDAR_CONFIG_URL` | `https://你的已备案域名/calendar/` | 可选：把校历配置从 HTTP 上游换成自己的 HTTPS 镜像 |

```bash
gh variable set PRIVACY_POLICY_URL --body "https://你的已备案域名/privacy.html"
gh variable set USER_AGREEMENT_URL --body "https://你的已备案域名/terms.html"
gh variable set DEVELOPER_NAME --body "胡天泽"
gh variable set ICP_FILING_NUMBER --body "浙ICP备XXXXXXXX号-XA"
gh variable set CALENDAR_CONFIG_URL --body "https://你的已备案域名/calendar/"
```

> `CALENDAR_CONFIG_URL` 可选。上游 `calendar.celechron.top` 目前只支持 HTTP，
> 应用市场隐私检测可能提示明文传输；把校历配置 JSON 镜像到自己的 HTTPS 域名后，
> 用它覆盖默认地址即可去掉这一项风险，同时更新隐私政策中的相关描述。

> 不设置也可以构建，应用会使用 `lib/utils/legal_links.dart` 里的默认 GitHub Pages 地址。但 GitHub Pages 在国内可能访问不稳定，**上架前强烈建议换成自己的已备案域名**。
> 仓库已包含 `.github/workflows/pages.yml`，推送到 `main` 后可自动部署 `docs/` 下的隐私政策页；私有仓库使用 GitHub Pages 通常需要 GitHub Pro/Team，或者改为部署到自己的服务器/对象存储。

## 6. 构建签名包

1. 确认代码在 `dev`/`main` 分支，版本号为 `0.1.7+100`。
2. GitHub → Actions → `Release to AppGallery` → `Run workflow`：
   - `platforms`: `both`（或先 `harmonyos`）
3. 构建产物在 Actions Artifacts：
   - `Helechron_0.1.7_ohos_signed.app`（**AppGallery 鸿蒙上架用这个**）
   - `Helechron_0.1.7_ohos_signed.hap`（本地真机安装测试）
   - `Helechron_0.1.7_android_signed.apk`（AppGallery 安卓上架用）
4. Android job 会自动用 `apksigner` 校验签名；鸿蒙 job 会优先收集 `*signed*.app`。

如果鸿蒙 `assembleApp` 失败：

- 用 DevEco Studio 打开 `ohos/`；
- 配置 release 签名；
- `Build` → `Build App(s)`；
- 用生成的 `.app` 上传。
- Flutter 侧的 HAP 已经由 `flutter build hap` 生成，DevEco 只需要打包成 App Pack。

## 7. 商店资料

完整可粘贴文案见 [listing.md](./listing.md)。

### 7.1 图标

- 商店图标：`store/appgallery/icon/helechron_icon_216.png`（216×216）
- 高清备用：`helechron_icon_1024.png` / `helechron_icon_512.png`
- 宣传图（如 AGC 要求）：`helechron_banner_1080x450.png`

### 7.2 截图

在真机（HarmonyOS NEXT）上截取，建议 3–8 张、9:16、JPG/PNG、单张不超过 8 MB（以 AGC 上传页为准）：

1. 首页“接下来”
2. 课程表 / 日历
3. 任务 / DDL
4. 学业 / 成绩（不要出现真实姓名、学号）
5. 设置页（展示隐私政策入口）
6. 桌面小组件
7. 付款码（可选；如担心支付类审核，首次可不放）

截图注意事项：

- 不要出现真实姓名、学号、成绩排名等个人信息；
- 不要出现浙大校徽/校名；
- 不要加过度营销文案或虚假界面；
- 保持与安装包实际 UI 一致。

### 7.3 隐私与权限申报

- 隐私政策 URL、用户协议 URL：填部署后的地址；
- 权限用途：见 `listing.md` 的权限表；
- 第三方 SDK：本应用没有广告/统计/崩溃上报 SDK；
- 数据收集：账号密码、课表/成绩、日历、用户选择的文件，均仅本地保存；
- 数据删除：退出登录、清除应用数据、卸载应用；
- 备案号、软著编号：拿到后填写。

## 8. 提交审核

1. AGC → 我的应用 → 选择应用 → 应用发布 → 提交版本。
2. 上传对应包：
   - 鸿蒙：`.app`
   - 安卓：`.apk`
3. 版本号必须与包内一致：`0.1.7` / `100`。
4. **提交前确认包内单层图标为 1024×1024**（`ohos/entry/src/main/resources/base/media/icon.png`、
   `ohos/AppScope/resources/base/media/app_icon.png`）；AGC 后台商店图标用 216×216 版本。
   单层图小于 1024×1024 会被以「应用图标单层图尺寸不满足 1024×1024」驳回。
5. 填写更新说明、测试账号、审核备注。
6. 提交审核。
7. 审核通过后选择“立即发布”或定时发布。

### 审核备注模板（可直接改）

> 本次驳回整改版本（覆盖开发者名称与主体类型、首次启动明示同意流程、包内单层图标
> 1024×1024 三点）见 [listing.md 第 8 节](./listing.md#8-审核备注模板)，直接用该版本。

```text
审核老师您好：

1. 开发者名称：胡天泽，主体类型：个人开发者（非企业主体），与 AGC 开发者信息一致；
   应用内用户协议、隐私政策、关于页展示的开发者名称同源同值。
2. 本应用 Helechron 是第三方开源课程表与时间管理工具，非浙江大学官方应用，
   也非 Celechron 官方应用，与浙江大学、Celechron 及其附属机构无隶属、授权或
   合作关系。应用内“关于”页和隐私政策均有相同声明。
3. 测试账号：账号 [填写]，密码 [填写]，验证方式 [填写]。
   登录路径：启动 → 同意隐私政策 → 设置 → 登录。
   核心功能路径：首页“接下来”、日历、任务、学业。
4. 本应用不提供支付、借贷、理财等金融服务。校园卡页面仅展示用户本人已登录
   账户的付款码，不进行支付清算，也不将凭据上传到任何开发者服务器。
5. 隐私政策首次启动同意页展示：默认未勾选的空白复选框，未勾选时“同意并继续”
   置灰不可点，底部常驻“不同意并退出应用”；同意前不读取账号、不联网。
   设置 → 关于 → 隐私政策 / 用户协议 可再次查看。在线地址：[填写]。
6. 应用为 GPL-3.0 开源项目，源码地址：
   https://github.com/Kepler16f/Helechron
7. 版本号：0.1.7（versionCode 100）；备案号：[填写]。
8. 若部分校园系统需要校园网/VPN，请使用测试账号在公网环境验证；
   如仍无法访问，请告知，我们会补充演示数据或说明。
```

## 9. 常见驳回与处理

| 驳回原因 | 处理 |
|---|---|
| 用户协议展示的公司名称与 AGC 开发者信息不一致 | 应用内开发者名称已统一到 `lib/utils/legal_links.dart` 的 `developerName`（默认 `胡天泽`，个人开发者），协议/隐私政策/关于页同源；确认 AGC 开发者信息里的名称与该值**逐字一致**，不一致时用 `--dart-define=DEVELOPER_NAME=...` 覆盖后重新构建 |
| 应用图标单层图尺寸不满足 1024×1024 | 包内 `ohos/entry/src/main/resources/base/media/icon.png` 与 `ohos/AppScope/resources/base/media/app_icon.png` 均为 1024×1024；商店后台上传 216×216 版本即可，两者为同一设计 |
| 隐私政策未以明示同意方式取得同意 | 已改为空白复选框默认未勾选 + 同意按钮置灰 + 「不同意并退出应用」常驻；确认构建包含 `consent_page.dart`，同意前不读取账号、不联网；隐私政策需有「六、同意的取得方式」章节 |
| 首次启动未展示隐私政策 | 已实现同意门；确认构建包含 `consent_page.dart` 且同意前不联网 |
| 隐私政策链接无法访问 | 换到已备案域名/国内可访问的 HTTPS 地址；同步更新 GitHub variable 并重新构建 |
| 未提供测试账号 / 核心功能无法验证 | 提供专用测试账号、验证方式、功能路径；必要时增加演示模式 |
| 图标/名称侵犯第三方权利 | 已换原创图标；介绍中保留非官方声明；如仍被问询，提供授权或彻底移除校名 |
| 缺少 APP 备案号 | 完成备案并回填 AGC；未注入时应用内显示 `【ICP备案号待补充】` 占位符，需用 `--dart-define=ICP_FILING_NUMBER=...` 重新构建 |
| 缺少软著 | 提供电子版权认证或软著证书 |
| 权限超范围/未说明 | 按 `listing.md` 权限表填写；确认包内没有多余权限 |
| 明文 HTTP 传输 | `calendar.celechron.top` 目前是 HTTP；在隐私政策中已披露。审核追问时说明用途，长期建议迁移 HTTPS |
| 应用内更新/诱导下载 | 应用只做版本检查并提示，不下载、不安装；如被问询如实说明 |
| 校园卡付款码被认定为支付功能 | 说明仅展示本人付款码、不涉及资金交易；首次审核可临时隐藏入口 |
| 崩溃/兼容性问题 | 在 HarmonyOS NEXT 真机复测；提供复现步骤和诊断日志 |
| 未成年人保护 | 年龄分级 3+，无 UGC、无社交、无付费；介绍中说明面向高校学生 |

## 10. 发布后维护

- 每次发版递增 `versionCode`（100 → 101 → …），同时更新：
  - `pubspec.yaml` 的 `version: 0.1.7+N`
  - `tool/pubspec_ohos.yaml`
  - `ohos/AppScope/app.json5`
  - `lib/worker/fuse.dart` 的 `build` 与 `displayVersion`
- 保留每个版本的签名包和 mapping（如有）；
- AGC 证书/Profile 到期前续期；
- 隐私政策实质变更时：
  1. 更新 `assets/legal/privacy_policy.txt`；
  2. 递增 `privacyPolicyVersion`；
  3. 重新生成 `docs/privacy.html`；
  4. 更新 AGC 的隐私政策 URL；
  5. 发版后用户会再次看到同意页。
- 保持测试账号可用，后续每次更新审核都会用到；
- 关注 AGC 的“审核意见”“用户评论”“崩溃”数据。

## 11. 参考链接

- 华为开发者联盟：<https://developer.huawei.com/consumer/cn/>
- AppGallery Connect：<https://developer.huawei.com/consumer/cn/service/josp/agc/index.html>
- 工信部备案系统：<https://beian.miit.gov.cn/>
- 中国版权保护中心：<https://www.ccopyright.com.cn/>
- Flutter-ohos SDK：<https://gitcode.com/openharmony-tpc/flutter_flutter>
- 项目源码：<https://github.com/Kepler16f/Helechron>
