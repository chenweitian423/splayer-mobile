# 开发说明

面向本仓库的开发文档。交接用的现场笔记（`HANDOFF.md`）**只在本地保留、不入库**。

---

## 1. 这是什么

一个手机端（Android / iOS）的**组件化播放器**：把 `.js` 组件当作脚本运行在沙箱里，
宿主（本 App）负责网络请求、内容解析与播放。运行时实现了
**CapyPlayer / Forward Widget** 组件规范，因此符合该规范的组件可以直接导入使用。

App 本身**不内置、不提供任何内容源**，只提供播放器与运行时。

---

## 2. 目录结构

```text
lib/
  main.dart              应用入口、底部导航壳、运行时宿主挂载点
  models/                数据模型（组件元数据 / 媒体条目 / 播放队列 / 分页）
  runtime/
    widget_runtime.dart  单个组件的运行时（WebView 沙箱 + JS 桥）
    plugin_engine.dart   运行时池：装载、复用、卸载、网络日志汇总
  store/
    plugin_store.dart    组件落盘 / 导入 / 启停
    history_store.dart   观看历史与播放进度
    app_settings.dart    应用设置（自动连播、自动检查更新…）
    update_service.dart  在线更新：查版本、下载安装包
    error_log.dart       全局异常捕获与落盘
  ui/                    各页面与通用控件
    layout.dart          自适应断点与尺寸度量（纯函数，有单测）
test/                    纯逻辑单元测试
.github/workflows/       CI：静态检查 / 单测 / Android / iOS / 发布
```

---

## 3. 架构要点

**三层职责**

| 层 | 职责 | 关键约束 |
|---|---|---|
| UI 层 | 列表、详情、播放、设置 | 不直接碰 JS；只通过 `WidgetRuntime` 的方法取数据 |
| 运行时层 | 每个组件一个 WebView 沙箱；代理组件发出的网络请求 | 组件之间互不干扰，可单独卸载 |
| 组件层（`.js`） | 声明元数据与取数逻辑 | 按 CapyPlayer / Forward Widget 规范编写 |

**运行时宿主为什么要挂在屏幕外**：WebView 必须有真实尺寸才会稳定执行 JS。
用 `Offstage` 会让它被挂起、定时器与回调失灵，所以宿主放在屏幕外（负坐标）而不是隐藏。

**数据流**：UI → `PluginEngine.runtimeFor(record)` 取运行时 → `runtime.callList(...)`
→ 运行时在 WebView 内调用组件函数 → 组件通过桥发起网络请求（宿主代发，避免跨域）
→ 结果回传并解析成 `MediaItem`。

---

## 4. 本地构建与验证

本机没有 Flutter 时，用与 CI 同版本的容器跑，结论与 CI 一致：

```bash
# 注意：Windows Git Bash 下需要这行，否则路径会被转换
export MSYS_NO_PATHCONV=1

docker run --rm \
  -v "$PWD:/work" -v splayer_pub_cache:/root/.pub-cache -w /work \
  ghcr.io/cirruslabs/flutter:3.32.0 bash -lc \
  "flutter pub get && flutter analyze && flutter test"
```

- 必须挂**持久 pub 缓存卷**（`splayer_pub_cache`），否则 `--rm` 退出后会出现假故障。
- `flutter analyze` 连 **info 级 lint 都算失败**，提交前必须清零。
- 另有运行时契约测试（本机有 Node 时跑）：`node tools/runtime-contract-test.mjs`。

---

## 5. 编码约定

- **超时兜底**：任何可能长时间不返回的异步调用（WebView 的 load / runJavaScript、
  网络请求）都要有超时，并让失败**可见**（页面出可点的错误，而不是无声转圈）。
- **不要把「可能永不返回」的 await 放进锁/队列**，否则会把整个队列拖死。
- **自适应只在一处**：断点与尺寸都放 `lib/ui/layout.dart`，不要在页面里写魔法数字。
- **播放队列是统一结构**：剧集是「集」，电影是「多条线路」；只有剧集才做自动连播。
- **列表保活**：滚动列表里的分区用 `AutomaticKeepAliveClientMixin` + 首屏缓存，
  避免滑回来重新加载。
- 改动前后各跑一次 `flutter analyze` 与 `flutter test`。

---

## 6. 发版流程

版本号写在 `pubspec.yaml` 的 `version: X.Y.Z+build`。

```bash
# ① 升 pubspec.yaml 的版本号
# ② 在 CHANGELOG.md 顶部补一段 `## vX.Y.Z`（这就是 Release 正文）
git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z   # ③
```

CI 在推 `v*` tag 时会：跑静态检查与单测 → 出 Android APK 与 iOS 未签名 IPA
→ 从 `CHANGELOG.md` 抽取本版段落作为 **Release 正文** → 发布。
若忘了写 CHANGELOG，Release 正文会直接提示补写。

**Android 签名**：CI 从仓库 Secrets 读取固定的 release keystore（4 个变量）。
没有配置时会回落到 debug 签名 —— 那种包**无法用于覆盖安装升级**。

---

## 7. 已知限制

- 组件封面图若走第三方 CDN 直连，能否显示取决于客户端网络可达性，App 无法代偿。
- iOS 产物为未签名 IPA，需要自行签名后才能安装。
