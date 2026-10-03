# HANDOFF · SPlayer Mobile

> ## ⚡ 启动包
>
> **① 一句话启动语**
> `接着做 SPlayer Mobile 项目：先读 C:\Users\47403\WorkBuddy\2026-10-03-23-40-41\splayer_mobile\HANDOFF.md 顶部的「⚡ 启动包」，照它继续。`
>
> **② 当前状态快照**
>
> | 项 | 值 |
> |---|---|
> | 仓库 | https://github.com/chenweitian423/splayer-mobile （public，默认分支 main） |
> | 本地工程 | `C:\Users\47403\WorkBuddy\2026-10-03-23-40-41\splayer_mobile` |
> | 版本 | **v1.0.1**（v1.0.0 已发布；v1.0.1 修了真机反馈的三个问题，见进展记录） |
> | 技术栈 | Flutter 3.32.0 / Dart 3.8，单代码库出 Android + iOS |
> | 运行时 | 每个组件一个 WebView 沙箱（`assets/runtime/capy_runtime.js` + jQuery 3.7.1） |
> | 校验 | 容器内 `flutter analyze` 零问题、`flutter test` 12/12；组件契约冒烟 `tools/widget-smoke.mjs` |
> | 起点依据 | 判定报告 `_recon\SPlayer_TV_1.8-组件兼容判定.md` + 判定器 `_recon\apk_widget_compat.py` |
>
> **③ 下一步待办（按优先级）**
> 1. **真机复测 v1.0.1**：红果首页应从「短剧」起步（不再空）、51吃瓜/帝果/黄豆/剧果/野果 应能进详情并播放（`loadDetail` 传参已修）。
> 2. 若仍有组件播不了：装包后进 **设置 → 网络日志**，复制全文发我 —— 里面能看到组件请求了什么、返回什么状态。
> 3. MissAV 属独立问题：它依赖后端 `/api/v1/discovery/sites/missav/routes` 下发线路 + `9527.men` 可达，App 侧只能如实报错，需内容源/网络侧解决。
> 4. 播放内核升级：需要 mpv 级能力（Profile 7 FEL / 更多封装）时把 `video_player` 换 `media_kit`。
> 5. 待补能力：`Widget.tmdb`、`sectionMode`、TV 大屏布局。
>
> **④ 铁律（踩过的坑）**
> - **不要试图 1:1 反编译还原**：原 TV 版是 Kotlin+Compose 编译产物（78MB / 13 dex / R8 混淆），Compose 编译期变换不可逆。只做 clean-room（同规范、同模型、同能力）。
> - **验证 Flutter 必须挂持久 pub 缓存卷**：`docker run -v <proj>:/work -v flutter_pub:/root/.pub-cache ... ghcr.io/cirruslabs/flutter:3.32.0`；否则 `--rm` 一退就报 `Target of URI doesn't exist`、甚至 Flutter 自身 `Matrix4 isn't defined`（假故障）。
> - **Git Bash 里要先 `export MSYS_NO_PATHCONV=1`**，否则 `-w /work` 被转成 Windows 路径，docker 报 working directory invalid。
> - **`flutter analyze` 连 info 级 lint 都算失败**（`unnecessary_import`、`unintended_html_in_doc_comment`），必须清零。
> - ★★ **`loadDetail` 只能传字符串**：8 支组件全吃字符串，其中 5 支会把参数直接当 URL 用 —— 传对象就是 `[object Object]`，表现是「详情页报 URI 错、无法播放」。宿主已做「字符串优先 + 对象回退」。
> - ★★ **首页别拿 `modules[0]`**：红果/MissAV 的第一模块是搜索，空关键词必然空列表 → 首页空白。用 `pickHomeModule()`。
> - **组件契约变了先跑 `node tools/widget-smoke.mjs <组件目录>`**：它会在 Node 沙箱里真跑每个模块，并断言宿主只传字符串 URL。
> - **WebView 宿主不能用 `Offstage`**（会 suspend 掉 JS），要屏幕外 `Positioned`。
> - **`runJavaScriptReturningResult` 两端不一致**：Android 返回带引号的 JSON 串、iOS 返回裸值 → 统一走 `WidgetRuntime._normalizeJsResult`。
>
> **⑤ 本文件怎么读**
> - 「⚡ 启动包」= 唯一权威现状（状态/待办/铁律只写这里，别处只引用）。
> - 「进展记录」= 倒序追加的历史，**已完成的段落不要重做**。
> - 「设计决策」= 为什么这么写，改代码前先看。

---

## 设计决策（勿轻易推翻）

| 决策 | 原因 |
|---|---|
| Flutter 单代码库 | 一份代码出 Android + iOS；CI 里 Android 用 ubuntu、iOS 用 macOS，成本最低 |
| 组件跑在 WebView 而非 QuickJS | 需要 `Widget.html.load` 的 cheerio 语义 —— WebView 自带真实 DOM，直接用 jQuery 就能当 cheerio 用；自己实现 CSS 子集风险太高 |
| HTTP 走原生而非 WebView fetch | 绕开 CORS，且能自由设 UA / Referer / timeout（组件普遍依赖这个） |
| 一个组件一个 WebView | 原 TV 版所有插件共用一个 JS 上下文，同名内部函数互相覆盖；分开后互不干扰、可单独卸载 |
| 4xx/5xx **resolve** 成 `{ok:false,status,data}` 而非 reject | 组件普遍写 `if (response.ok === false) throw ...`，resolve 才走它们自己的分支；只有传输层错误才 reject（带 `.status` / `.response.data`） |
| 播放用官方 `video_player` | CI 出包最稳；mpv 能力后置 |

## 进展记录（倒序）

### 2026-10-04 · v1.0.1 修三个真机问题（用户在 iOS 装机后反馈）

真机反馈：导入 happy-capy 全部组件后，① 红果/MissAV 首页空白 ② 只有红果能播 ③ 出现 `No host specified in URI %5Bobject%20Object%5D`。

**根因（用 `tools/widget-smoke.mjs` 在 Node 沙箱里跑真组件坐实）**：

1. ★★ **`loadDetail` 参数传错了**（这是"只有红果能播"的唯一原因）：宿主必须传**字符串**。实测 8 支组件全部吃字符串，但 51吃瓜/帝果/黄豆/剧果/野果 5 支会把参数**直接丢给 `Widget.http.get`** —— 传对象 → URL 变成 `[object Object]`（即截图里那条 URI 错）→ 详情页挂掉 → 无法播放。红果/黄果/MissAV 写了 `typeof link === "object"` 容错分支，所以只有红果能播。
   修法：`loadDetail(MediaItem)` 先传 `item.link` 字符串，失败再回退传对象（兼容两种野写法）。
2. **首页取了 `modules[0]`，而红果/MissAV 的 `modules[0]` 是搜索模块**：空关键词下必然返回空数组 → 首页空白。
   修法：`pickHomeModule()` 三级回退：非搜索非历史 → 非搜索 → 第一个（红果从「搜索短剧」顺延到「短剧」）。
3. 顺带加固：
   - JS 侧拦下非字符串 URL，错误里直接报真实类型，不再产生看不懂的 URI 报错；
   - **把 WebView 的 `fetch` 也接到原生通道**（消 CORS，让「Widget.http 优先 + fetch 兜底」的双通道真正可用）；
   - 空列表有文案（不再是一片空白）；
   - 新增**网络日志**页（设置 → 网络日志，可一键复制），每个请求的 URL/状态/耗时/字节数都在，远程排障靠它。

**MissAV 另有独立问题（非本次代码问题）**：它的所有模块都会抛
`X99 暂无 MissAV 直接访问地址（Runtime 无线路：/api/v1/discovery/sites/missav/routes，直接线路 0；9527.men 非 X99 导航页）`
—— 依赖后端下发线路 + `9527.men` 可达，属内容源/网络侧，App 侧只能把这条错误如实显示出来。

### 2026-10-04 · v1.0.0 首版
- 从 APK 判定出发（`SPlayer_TV_1.8.apk` → 内置 CapyPlayer 兼容运行时，8 个组件全可跑），确定 clean-room 复刻方案。
- 落地 Flutter 工程：运行时 / 组件仓库 / 首页·分类·详情·播放 / 插件管理 / 搜索 / 设置。
- 容器内验证：`flutter analyze` 零问题、`flutter test` 7/7 通过、`flutter build apk --release` 成功（55MB）。
- GitHub 仓库建立（public），CI 四 job：analyze → android(27MB APK) → ios(23MB 未签名 IPA) → release(tag)。
