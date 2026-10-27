# Helechron

<div style="text-align: center; ">


服务于浙大学生的时间管理器 Celechron 的 HarmonyOS NEXT 构建

日程一览 · 课表查看 · DDL 助手 · 成绩查询

</div>

## 平台支持

| 平台 | 状态 |
|------|------|
| HarmonyOS NEXT (API 12+) | ✅ |

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
- **学业 (Scholar)** — 课程列表、成绩查询、考试列表
- **设置 (Option)** — 登录、校园卡付款码、深色模式、系统日历同步

### HarmonyOS NEXT 适配说明

本项目通过 Flutter-ohos (OpenHarmony Flutter 分支) 适配到 HarmonyOS NEXT。

**已适配功能：**
- 核心 UI 和业务逻辑
- 网络请求和数据同步（参考elychron项目进行数据刷新保护；通过更改请求头提高刷新成功概率）
- 本地存储 (Hive)
- 课程表导出/导入 (iCal)
- 校园卡付款码
- 应用图标（原创时钟 / 笔记本图标，单层图 1024×1024，不含任何高校校名或校徽元素）
- 深色模式完整支持
- 本地通知推送（成绩变动提醒、DDL 截止提醒）
- 后台定时刷新（通过 MethodChannel 桥接 ArkTS 原生能力）
- 系统日历同步（通过 ArkTS Calendar Kit 将课程表同步到系统日历）
- 关于页面（含上游 Celechron 项目链接）
- ArkTS原生实现悬浮底栏和沉浸光感
- 桌面课程倒计时和课程简报小组件
- 桌面付款码小组件（点击放大按钮可弹窗放大，快捷直达付款码）

## 许可证

[GPL-3.0](LICENSE)
