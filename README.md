# SPlayer Mobile

手机端的组件化播放器（Android / iOS）， SPlayer 的能力面：把 `.js` 组件当脚本跑在沙箱里，宿主负责网络、解析、播放。

> 这里做的是：**同一套组件规范、同一套数据模型、同样的能力**，UI 按手机重做 —— 因此现成的 `.js` 组件可以直接复用。

## 组件规范兼容性

运行时实现了 CapyPlayer / Forward Widget 规范（这套规范同时被 Forward、CapyPlayer 使用）：

| 能力 | 状态 | 实现位置 |
|---|---|---|
| `WidgetMetadata`（含 `title`/`name`、`icon`/`iconUrl`、`globalParams`） | ✅ | `lib/models/capy_models.dart` |
| `modules[].functionName`（含 `a.b` 点路径） | ✅ | `assets/runtime/capy_runtime.js` |
| `Widget.http.get/post/put/request`（`timeout`/`headers`/`params`，返回 `{ok,status,data,headers}`） | ✅ | 原生 `http` 直连，绕开 WebView 的 CORS |
| `Widget.html.load(html)`（cheerio 等价物） | ✅ | 内置 jQuery 3.7.1 |
| `Widget.dom.parse/select/text/attr/remove` | ✅ | 原生 DOM + 句柄表 |
| `Widget.storage.get/set/getAsync/remove` | ✅ | 按组件命名空间隔离 |
| `Widget.tmdb.get` | ❌ | 需要 TMDB API Key，未内置 |
| `loadDetail` → `videoUrl` / `playSources` / `seasons` / `episodeItems` | ✅ | `lib/ui/detail_page.dart` |
| `globalParams` 合并进每个模块参数 | ✅ | `WidgetRuntime.buildParams` |
| WebView 内的 `fetch` 也走原生通道 | ✅ | 消掉壳 origin 引起的 CORS（组件「Widget.http 优先 + fetch 兜底」的双通道写法才真正可用） |

### 三个必须知道的组件约定（踩过坑）

| 约定 | 事实 | 我们的处理 |
|---|---|---|
| `loadDetail(link)` 的参数 | **必须是字符串**。实测 8 支组件全部吃字符串，其中 5 支（51吃瓜/帝果/黄豆/剧果/野果）会把参数**直接当 URL** 用 —— 传对象就变成 `[object Object]`，详情页挂掉、无法播放 | 先按规范传字符串；失败再回退传条目对象（红果/黄果/MissAV 支持对象写法） |
| 首页该取哪个模块 | 组件常把**搜索**放在 `modules[0]`（红果、MissAV 都是），空关键词下必然返回空列表 → 首页一片空白 | `pickHomeModule()` 三级回退：非搜索非历史 → 非搜索 → 第一个 |
| 桥接参数编码层次 | 值 → `jsonEncode`（JSON 文本）→ `jsonEncode`（JS 字符串字面量），**三层缺一不可**。少一层，JS 的 `JSON.parse` 拿到的不是字符串，参数静默变 `{}`/`null` —— 真机现象是「所有组件一起报 `组件传入的是 null`」 | 统一走 `buildInvokeExpression()`，由单测与 Node 契约测试双重把关 |
| 组件的**播放内核** | 组件可能把内核写死（实测 MissAV：`var MISSAV_PLAYER_MODE = "mpv"`），并据此向后端要 **mpv 专用清单** —— 系统播放器（AVPlayer/ExoPlayer）拿到只会报 `unsupported URL (-1002)` | 两道保险：装载后 `__capyApplyHostPlayerMode("hls")` 掰全局常量；播放入口用 `playUrlCandidates()` 展开候选链（`player=mpv` → `player=hls` 优先，原地址兜底） |

## 播放器

| 能力 | 说明 |
|---|---|
| 队列化播放 | 剧集 = 集、电影 = 线路，详情页把整条队列交给播放器 |
| 竖滑切集 | **上滑下一集 / 下滑上一集**，带顶部提示浮层 |
| 选集面板 | 底部抽屉网格，随时跳集 |
| 倍速 | 0.5x / 0.75x / 1x / 1.25x / 1.5x / 2x |
| 线路切换 | 自动失败换源 + 手动换线路（含组件 `playSources` 当作同集备用线路） |
| 失败处理 | 全部候选失败才报错，可「重试 / 换线路 / 复制错误」一键反馈 |
| 外挂播放器 | 可交给系统播放器打开 |

换组件或改桥接层后，先跑这两个工具（CI 也会跑第二个）：

```bash
node tools/widget-smoke.mjs <组件目录> [关键词]   # 真跑外部组件，断言宿主只传字符串 URL
node tools/runtime-contract-test.mjs               # 装真实运行时，断言组件实际收到的参数
```

每个组件跑在**独立的 WebView** 里（原 TV 版是所有插件共用一个上下文，同名内部函数会互相覆盖），互不干扰、可单独卸载。

## 目录结构

```
lib/
  main.dart                     应用入口 + 底部导航（首页/搜索/插件/设置）
  models/capy_models.dart       组件数据模型（含字段别名兜底）
  models/play_queue.dart        播放队列与候选线路（mpv→hls 改写、失败换源）
  runtime/widget_runtime.dart   运行时：WebView 沙箱 + 双向桥
  runtime/plugin_engine.dart    运行时池，并把 WebView 挂在屏幕外保活
  store/plugin_store.dart       组件落盘 / 导入 / 托管页扫描
  ui/                           首页 · 分类 · 详情 · 播放 · 插件管理 · 搜索 · 设置
  ui/netlog_page.dart           网络日志（每个请求的 URL/状态/耗时，排障用）
tools/widget-smoke.mjs          组件契约冒烟测试（Node 沙箱真跑外部组件）
tools/runtime-contract-test.mjs 桥接层契约测试（Node 沙箱装真实运行时，CI 会跑）
assets/runtime/
  capy_runtime.js               注入到 WebView 的 window.Widget
  jquery.min.js                 Widget.html.load 的 DOM 引擎
```

## 导入组件

四种方式（插件页右下角 +）：

1. **网络地址** —— 粘贴 `.js` 直链；
2. **组件托管页批量导入** —— 粘贴托管页地址，自动列出页面上出现的全部 `.js` 并逐个校验是否含 `WidgetMetadata`，勾选后批量导入；
3. **剪贴板** —— 支持直链或整段源码；
4. **本地文件** —— 选 `.js`。

组件落盘在 `<应用文档目录>/plugins/`（`plugins.json` + `<id>.js` 快照），删除只影响本地快照。

## 构建

本仓库不依赖任何私钥：**没有配置 secrets 时用 debug 签名出包（同样可安装）**。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release        # 产物 build/app/outputs/flutter-apk/app-release.apk
flutter build ios --release --no-codesign
```

CI（`.github/workflows/build.yml`）在 push / PR / tag 时自动跑，产出 Android APK 与 iOS 未签名 IPA：

- `analyze` —— `flutter analyze` + `flutter test`
- `android` —— release APK，Artifacts 名 `android-apk`
- `ios` —— 未签名 IPA（`flutter build ios --no-codesign` + 打包 Payload），Artifacts 名 `ios-ipa`
- `release` —— 打 `v*` tag 时把两个包挂到 Release

想要正式签名，在仓库 Settings → Secrets 里加四个：

| Secret | 说明 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore 的 base64（`base64 -w0 your.jks`） |
| `ANDROID_KEY_ALIAS` | keyAlias |
| `ANDROID_KEY_PASSWORD` | keyPassword |
| `ANDROID_STORE_PASSWORD` | storePassword |

iOS 侧要装到真机，需要一个 Apple 开发者账号对 IPA 重签名（本仓库只出未签名包，不托管证书）。

## 已知限制

- iOS 的未签名 IPA 需要自签（AltStore / Sideloadly / 开发者证书）才能安装。
- 播放走官方 `video_player`（ExoPlayer / AVPlayer）。原版用 mpv 内核支持更多奇特封装（如 Profile 7 FEL 双层杜比视界），本版暂不支持；需要时可以换 `media_kit`。
- 未实现 `sectionMode` / `requiresWebView` 等边角能力。
- 组件最终可用性取决于它依赖的内容源是否可达 —— 组件负责解析，宿主负责取流。

## 免责声明

本应用**只提供播放器与组件运行时**，不内置、不托管、不提供任何内容源。组件的获取与使用请自行确保来源合法可信 —— 组件会以脚本形式在应用内运行。
