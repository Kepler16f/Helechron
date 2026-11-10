# Helechron

<div style="text-align: center; ">


Helechron 是基于 Celechron 开源项目移植并扩展功能的非官方版本，由胡天泽负责移植适配、独立开发新增功能及后续维护与发布。本应用不是 Celechron 官方应用，不代表 Celechron 原项目或其维护团队，也不是浙江大学官方应用。

本项目按 GPL-3.0 许可证使用和分发相关开源代码。保留原项目与贡献者署名仅用于说明代码来源，不代表 Celechron 原项目对本应用的官方身份、品牌使用或发布提供授权、合作或背书。

日程一览 · 课表查看 · DDL 助手 · 成绩查询

</div>

## 平台支持

| 平台 | 状态 |
|------|------|
| HarmonyOS NEXT (API 12+) | ✅ |
| Android | ✅ |
| iOS | ✅ |

## 构建 HarmonyOS NEXT 应用

### 前置条件

- DevEco Studio 5.0 或更高版本
- HarmonyOS NEXT SDK (API 12+)
- Flutter-ohos SDK (OpenHarmony Flutter 分支)

### 本地构建

```bash
# 1. 克隆 Flutter-ohos SDK
git clone https://gitcode.com/openharmony-tpc/flutter_flutter.git -b 3.27.5-ohos-1.0.8
export PATH="<flutter_flutter_path>/bin:$PATH"

# 2. 安装依赖
flutter pub get

# 3. 构建 HAP
flutter build hap --release
```

### GitHub Actions 自动构建

项目配置了 GitHub Actions 工作流，推送代码后会自动构建 HAP 安装包。

1. 前往仓库的 Actions 页面
2. 选择 "Build HarmonyOS HAP" 工作流
3. 点击 "Run workflow" 手动触发，或等待 push 自动触发
4. 构建完成后在 Artifacts 中下载 HAP 文件（直接输出 .hap，无需解压）

### 使用 DevEco Studio

1. 使用 DevEco Studio 打开项目下的 `ohos/` 目录
2. 配置签名证书（调试或发布）
3. 点击 Run 运行调试，或 Build > Build Hap(s) 打包

## 发布到华为应用市场（AppGallery）

- 完整上架手册（账号、备案、软著、签名、送审、驳回处理）：[store/appgallery/README.md](store/appgallery/README.md)
- 商店文案、权限与隐私申报表：[store/appgallery/listing.md](store/appgallery/listing.md)
- 签名发布工作流：`.github/workflows/release-appgallery.yml`（手动触发，产出签名 `.app` / `.apk`）
- 隐私政策与用户协议：`docs/privacy.html`、`docs/terms.html`
- 当前发布版本：`0.1.7`（versionCode `100`）

首次上架前需要完成：华为开发者实名认证、工信部 APP 备案、AGC 发布证书/Profile、
可用测试账号、商店截图，以及软件著作权/电子版权（如审核要求）。

上架前另需注意两点：

- **开发者名称必须一致**：AGC「开发者信息」里的开发者名称、应用内用户协议/隐私政策/
  关于页展示的开发者名称必须是同一个字符串（默认 `胡天泽`，个人开发者，非企业主体），
  不一致会被以「用户协议展示的公司名称与开发者信息不一致」驳回。
- **ICP 备案号**：拿到备案号后需回填 AGC，并重新构建让应用内「设置 → 关于」展示；
  未注入时应用内显示占位符 `【ICP备案号待补充】`。

版本保持 `0.1.7`（versionCode `100`），提交审核时以包内实际版本为准。

## 功能说明

### 核心功能

- **"接下来" (Flow)** — 时间流视图，展示即将发生的事件
- **日程 (Calendar)** — 日历视图，展示每日课表和日程安排
- **任务 (Task/DDL)** — 截止日期管理器
- **学业 (Scholar)** — 课程列表、成绩查询、考试列表、二三四课堂与培养方案进度、智云课堂应用内直播/回放与 PPT/字幕、学在浙大/智云课件下载与原生打开方式
- **设置 (Option)** — 登录、校园卡付款码（含自定义低余额预警阈值与桌面大码预警）、校园卡月度账单与分类消费统计、考前 1 小时通知提醒、课件下载路径配置、深色模式、系统日历同步

### HarmonyOS NEXT / Android / iOS 适配说明

本项目通过 Flutter-ohos (OpenHarmony Flutter 分支) 及原生插件通道同时适配 HarmonyOS NEXT、Android 与 iOS 三端。

**已适配与扩展功能：**
- 核心 UI 和业务逻辑（含考试周紧凑倒计时横幅、日历指定日期跳转、调休补课换日映射）
- 网络请求和数据同步（参考 Elychron 项目进行数据刷新保护；通过更改请求头提高刷新成功概率；支持节流防抖）
- 本地存储 (Hive) 与数据备份恢复
- 课程表导出/导入 (iCal)
- 校园卡付款码、自定义低余额预警阈值（支持付款码页与桌面大码弹窗同步预警）
- 校园卡月度流水账单与分类消费统计（餐饮/商超/水电占比与常去商户排行）
- 智云课堂应用内原生视频/直播播放、课堂 PPT 幻灯片浏览保存、课堂语音转写字幕检索
- 学在浙大与智云课堂课件一键下载、自定义保存路径与系统原生“打开方式”弹窗调用
- 本地通知推送（成绩变动提醒、DDL 截止提醒、考试前 1 小时考场/座位/物品清单提醒）
- 后台定时刷新（通过 MethodChannel 桥接 ArkTS / Android / iOS 原生能力）
- 系统日历同步（通过 ArkTS Calendar Kit / DeviceCalendar 将课程表同步到系统日历）
- ArkTS 鸿蒙原生 / Flutter 原生悬浮底栏与液态玻璃沉浸光感
- 桌面课程倒计时、课程简报与付款码小组件（HarmonyOS / Android / iOS）

## 致谢与参考开源项目

Helechron 在移植适配与新功能研发过程中，参考或使用了以下优秀开源项目的代码、接口协议整理或思路设计，特此致以诚挚感谢（排名不分先后）：

1. **[Celechron/Celechron](https://github.com/Celechron/Celechron)**
   - 上游原项目，提供时间流规划算法、基础架构与核心 UI 设计。
2. **[Elyyyyyyyyxer/Elychron](https://github.com/Elyyyyyyyyxer/Elychron)**
   - 参考其数据刷新防降级保护机制与校园网请求头优化方案。
3. **[5dbwat4/login-ZJU](https://github.com/5dbwat4/login-ZJU)**
   - 参考其浙大统一身份认证 (ZJUAM)、学在浙大 (`courses.zju.edu.cn`) 与智云课堂 CAS/OAuth2 登录握手与重定向链实现。
4. **[PeiPei233/zju-learning-assistant](https://github.com/PeiPei233/zju-learning-assistant)**
   - 参考其学在浙大活动附件/作业课件列表解析、智云课堂直播流 (`getscreenstream`) 与录播目录接口协议。
5. **[8eoyw/zju-learning-cli](https://github.com/8eoyw/zju-learning-cli)**
   - 参考其学在浙大课件多级回退下载（含仅预览文档 `preview=true` 签名直链提取）与教务接口设计。
6. **[Anchorite-no/zju-skill-public](https://github.com/Anchorite-no/zju-skill-public)**
   - 参考其智云课堂单节详情 (`get-sub-info`)、PPT 幻灯片抓取 (`search-ppt`) 与语音转写字幕 (`search-trans-result`) 接口协议。
7. **[Lucent-Snow/zju-scholar](https://github.com/Lucent-Snow/zju-scholar)** & **[iamNCJ/ZJU-Tronclass-Courseware-Downloader](https://github.com/iamNCJ/ZJU-Tronclass-Courseware-Downloader)**
   - 参考其智云课堂及学在浙大 TronClass 课件下载相关 API 端点整理。
8. **[determ1ne/zju_ecard](https://github.com/determ1ne/zju_ecard)**、**[OpenAHU/AHUTong-Android](https://github.com/OpenAHU/AHUTong-Android)**、**[Mercury000/HUEL-yktwx](https://github.com/Mercury000/HUEL-yktwx)**、**[Chiu-xaH/HFUT-Schedule](https://github.com/Chiu-xaH/HFUT-Schedule)**
   - 参考其新中新 (Synjones / 慧新e校) 校园一卡通 `berserker-app` / `berserker-search` 卡片余额、付款码及个人流水账单 (`search/personal/turnover`)、收支统计 (`statistics/turnover/count`) 接口协议。
9. **[OpenHarmony-TPC / flutter_flutter](https://gitcode.com/openharmony-tpc/flutter_flutter)** & **[openharmony-sig / flutter_packages](https://gitcode.com/openharmony-tpc/flutter_packages)**
   - 提供 HarmonyOS NEXT 平台的 Flutter 引擎与三方插件适配支持。

## 许可证

[GPL-3.0](LICENSE)
