# Helechron

<div style="text-align: center; ">


服务于浙大学生的时间管理器Celechron的HarmonyOS NEXT构建

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
git clone https://github.com/niceSaber/flutter_flutter.git
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
4. 构建完成后在 Artifacts 中下载 HAP 文件

### 使用 DevEco Studio

1. 使用 DevEco Studio 打开项目下的 `ohos/` 目录
2. 配置签名证书（调试或发布）
3. 点击 Run 运行调试，或 Build > Build Hap(s) 打包

## 功能说明

### 核心功能

- **"接下来" (Flow)** — 时间流视图，展示即将发生的事件
- **日程 (Calendar)** — 日历视图，展示每日课表和日程安排
- **任务 (Task/DDL)** — 截止日期管理器
- **学业 (Scholar)** — 课程列表、成绩查询、考试列表
- **设置 (Option)** — 登录、校园卡付款码

### HarmonyOS NEXT 适配说明

本项目通过 Flutter-ohos (OpenHarmony Flutter 分支) 适配到 HarmonyOS NEXT。

**已适配功能：**
- 核心 UI 和业务逻辑
- 网络请求和数据同步
- 本地存储 (Hive)
- 课程表导出 (iCal)
- 校园卡付款码

**暂未实现功能：**
- 后台定时刷新 (需 HarmonyOS Background Tasks API)
- 本地通知推送 (需 HarmonyOS Notification Kit)
- 系统日历同步 (需 HarmonyOS Calendar Kit)
- 原生桌面小组件 (需 HarmonyOS Form Kit)

## 许可证

[GPL-3.0](LICENSE)
