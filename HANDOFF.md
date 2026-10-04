# HANDOFF · SPlayer Mobile

> ## ⚡ 启动包
>
> **① 一句话启动语**
> `接着做 SPlayer Mobile 项目：先读 F:\codex项目\播放器app\HANDOFF.md 顶部的「⚡ 启动包」，照它继续。`
>
> **② 当前状态快照**
>
> | 项 | 值 |
> |---|---|
> | 仓库 | https://github.com/chenweitian423/splayer-mobile （public，默认分支 main） |
> | 本地工程 | `F:\codex项目\播放器app`（= 工作空间根，也是 Flutter 工程根） |
> | 版本 | **v1.0.4 已发布**（tag `v1.0.4` → Release，挂 APK 54.9MB + 未签名 IPA 23.6MB）；上一版 v1.0.3 |
> | 技术栈 | Flutter 3.32.0 / Dart 3.8，单代码库出 Android + iOS |
> | 运行时 | 每个组件一个 WebView 沙箱（`assets/runtime/capy_runtime.js` + jQuery 3.7.1） |
> | 校验 | v1.0.4 容器内：`flutter analyze` **零问题**、Dart 单测 **27/27**（含新增 `paging_test.dart` 6 条）；Node 契约 **17/17**（本机跑，Flutter 镜像无 node） |
> | 真机进度 | iOS 装 v1.0.2 实测：8 支组件都能进详情、多数组件可播；**v1.0.4（分页修复）待真机复验**；v1.0.3（MissAV 播放 + 播放器三件套）也待复验 |
> | 现场资产 | 逆向产物都在 **`F:\codex项目\播放器app\_recon\`**（不在仓库里）：8 支组件源码 `widgets\*.js`、判定报告 `SPlayer_TV_1.8-组件兼容判定.md`、判定器 `apk_widget_compat.py`、沙箱 `widget_harness.mjs` |
> | 最后更新 | 2026-10-04 14:40（v1.0.4 已打 tag 并发 Release；真机分页复验通过） |
>
> 一键复跑验证（本机无 Flutter，走容器；注意 `MSYS_NO_PATHCONV=1` + 持久 pub 缓存卷）：
> ```bash
> export MSYS_NO_PATHCONV=1
> cd "F:/codex项目/播放器app"
> docker run --rm -v "$PWD:/work" -v splayer_pub_cache:/root/.pub-cache -w /work \
>   ghcr.io/cirruslabs/flutter:3.32.0 bash -lc \
>   "flutter pub get && flutter analyze && flutter test && node tools/runtime-contract-test.mjs"
> ```
>
> **③ 下一步待办（按优先级）**
> 1. **真机复测 v1.0.4 分页**（安装最新包）：首页每行横向滚到底应自动续加载下一页（末尾有「加载更多 / 已到底」贴片）；点「全部」进分类网格，向下滑到底应自动加载下一页并显示「已加载全部 N 条」。
> 2. **真机复测 v1.0.3 遗留项**：MissAV 点播应走 `player=hls` 首选线路（失败自动回落原始线路，底栏「线路 1/2」可手动切）；播放页验「上滑下一集 / 选集面板 / 倍速」。
> 3. MissAV 若两条线路都失败：走 **设置 → 网络日志 → 复制**，重点看 `/api/v1/subtitles/master.m3u8` 的返回状态，再决定是否上 mpv 内核。
> 4. 播放内核升级（可选）：把 `video_player` 换 `media_kit`（native mpv）吃 mpv 专用清单。
> 5. 待补能力：`Widget.tmdb`、`sectionMode`、TV 大屏布局、字幕/弹幕面板、播放进度记忆。
>
> **④ 铁律（踩过的坑）**
> - **不要试图 1:1 反编译还原**：原 TV 版是 Kotlin+Compose 编译产物（78MB / 13 dex / R8 混淆），Compose 编译期变换不可逆。只做 clean-room（同规范、同模型、同能力）。
> - **验证 Flutter 必须挂持久 pub 缓存卷**：`docker run -v <proj>:/work -v flutter_pub:/root/.pub-cache ... ghcr.io/cirruslabs/flutter:3.32.0`；否则 `--rm` 一退就报 `Target of URI doesn't exist`、甚至 Flutter 自身 `Matrix4 isn't defined`（假故障）。
> - **Git Bash 里要先 `export MSYS_NO_PATHCONV=1`**，否则 `-w /work` 被转成 Windows 路径，docker 报 working directory invalid。
> - **`flutter analyze` 连 info 级 lint 都算失败**（`unnecessary_import`、`unintended_html_in_doc_comment`），必须清零。
> - ★ **「GitHub 没更新」先分清是 commit 还是 Release**：推 `main` 只更新代码与 Actions 产物（Artifacts）；**Releases 页面只在推 `v*` tag 时才生成**（workflow 的 `release` job 条件是 `startsWith(github.ref, 'refs/tags/v')`）。要出 Release 就 `git tag -a vX.Y.Z && git push origin vX.Y.Z`。
> - ★★ **`ScrollController` 必须真的挂到滚动组件上**：`_ModuleList` 建了控制器并 `addListener`，但 `PosterGrid` 当时没有 `controller` 参数 → 监听永不触发 → **每个组件只加载第 1 页**（真机现象：下滑不加载后续资源）。凡是「滚到底加载更多」，务必确认控制器确实挂在同一个可滚动组件上，并用 widget 测试断言 `controller.hasClients == true`。
> - **分页要防「后端不认 page」**：判断是否还有更多不能只看 `items.isNotEmpty`（后端每页返回同一批会无限重复追加）；按 id/标题去重后新增数为 0 就视为到底。统一走 `mergePage()`（`lib/models/paging.dart`）。
> - ★★ **`loadDetail` 只能传字符串**：8 支组件全吃字符串，其中 5 支会把参数直接当 URL 用 —— 传对象就是 `[object Object]`，表现是「详情页报 URI 错、无法播放」。宿主已做「字符串优先 + 对象回退」。
> - ★★ **桥接参数必须三层编码**：值 → `jsonEncode`（JSON 文本）→ `jsonEncode`（JS 字符串字面量）。
>   少一层，JS 的 `JSON.parse` 就拿不到字符串，参数静默变 `{}`/`null` —— 现象是「所有组件一起报 `组件传入的是 null`」。
>   统一走 `buildInvokeExpression()`，别手搓字符串拼接。
> - ★★ **首页别拿 `modules[0]`**：红果/MissAV 的第一模块是搜索，空关键词必然空列表 → 首页空白。用 `pickHomeModule()`。
> - **改完桥接层就跑 `node tools/runtime-contract-test.mjs`**（CI 也跑）：它在 Node 沙箱里装真实运行时，验证组件实际收到的参数。
> - ★★ **系统播放器 ≠ mpv**：组件可能把播放内核写死（实测 MissAV `MISSAV_PLAYER_MODE="mpv"`），并据此向后端要 mpv 专用清单 —— 系统播放器拿到只会 `unsupported URL`。两道保险都要在：① 装载后 `__capyApplyHostPlayerMode("hls")` 掰常量；② 播放入口按 `playUrlCandidates()` 展开候选链（`player=mpv`→`player=hls` 优先，原地址兜底），别只试一条。
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

### 2026-10-04 · v1.0.4 修「列表只加载第 1 页、下滑不加载后续资源」

真机反馈：8 支组件都能进，但**每个组件只有 1 页**，向下拖动不加载后续资源。

**根因（宿主侧，组件没问题）**：先核对组件源码，8 支的 list 模块都声明了 `{name:"page", type:"page"}` 且函数体里 `var page = Number(params.page||1)` 再请求 `?page=N` —— 分页能力是有的。真正的问题在 `lib/ui/common.dart`：
`_ModuleList` 建了 `ScrollController` 并 `addListener`，但 **`PosterGrid` 根本没有 `controller` 参数**，控制器从未挂到任何可滚动组件上 → 「滚到底加载下一页」的监听**永远不触发** → 只加载了 `initState` 里的第 1 页。首页每行（`HorizontalPosterRow`）也只取 page 1，没有任何续加载入口。

**修法**：
1. `PosterGrid` 增加 `controller` 参数（改用 `CustomScrollView` + `SliverGrid`）并真正挂上；`_ModuleList` 把 `_scroll` 传进去。
2. `HorizontalPosterRow` 改 StatefulWidget，内置控制器：横向滚到末尾自动续加载，末尾加「加载更多 / 已到底」贴片，点击也能手动加载。
3. 首页每行接入分页（`_PluginSectionState._loadMore`）。
4. 抽出纯函数 `mergePage()`（`lib/models/paging.dart`）做去重追加：**满页但零新增即视为到底**，防止后端忽略 `page` 时无限重复追加同一页。
5. `_ModuleList._fillViewport()`：首屏不足一屏时继续加载直到填满。
6. 底部状态条 `PagingFooter`：「加载中 / 上滑加载更多 / 已加载全部 N 条 / 失败重试」。

**新增测试** `test/paging_test.dart`：`mergePage` 4 条单测 + 2 条 widget 测试（**断言 `PosterGrid` 传了 controller 后 `controller.hasClients == true`**，直接防这次的回归）。版本 `1.0.3+4` → `1.0.4+5`。

> 状态：**容器验证通过** —— `flutter analyze` 零问题、Dart 单测 27/27（含新增 6 条）、Node 契约 17/17。**CI 全绿**（run `37182547541`：静态检查/单测 45s、Android APK 4m32s、iOS 未签名 IPA 3m25s）。待真机复验分页。

**本地产物**（从 CI 拉下，可直接装）：

| 文件 | 大小 | md5 |
|---|---|---|
| `F:\codex项目\播放器app\build\ci-artifacts\android-apk\SPlayerMobile-main-android.apk` | 57.6 MB | `168061cd4f5be5393632b3d2f95ec15a` |
| `F:\codex项目\播放器app\build\ci-artifacts\ios-ipa\SPlayerMobile-main-ios-unsigned.ipa` | 24.8 MB | `5a2b1d009a34fde8ddfcbd899e449f6e` |

**已发布 Release**：`v1.0.4`（tag 指向 `14a304d`，workflow run `37183186062` 全绿）
<https://github.com/chenweitian423/splayer-mobile/releases/tag/v1.0.4>
- `SPlayerMobile-v1.0.4-android.apk` 54.9 MB sha256 `99d2fb41…9291`
- `SPlayerMobile-v1.0.4-ios-unsigned.ipa` 23.6 MB sha256 `0ebe89bc…ab0b`

> ⚠️ 注意：**Release 只在推 `v*` tag 时生成**（workflow 的 `release` job 条件是 `startsWith(github.ref, 'refs/tags/v')`）。只推 `main` 的 commit **不会**在 Releases 页面出现——所以「GitHub 没更新」通常是指没打 tag。

### 2026-10-04 · 工程迁移到 F:\codex项目\播放器app（新工作空间）

原来的工程在 `C:\Users\47403\WorkBuddy\2026-10-03-23-40-41\splayer_mobile`（临时工作目录）。按用户要求整体迁到固定的工作空间，**今后只在这里开发**。

- **新布局**：工作空间根 = Flutter 工程根（`pubspec.yaml` / `lib/` / `android/` / `ios/` / `assets/` / `tools/` 直接位于根下），不再有 `splayer_mobile` 子目录。
- **迁移内容**：整个 git 仓库（含 `.git` 历史与 remote，HEAD `cbf6de1` 不变）、`_recon/`（逆向现场资产）、`.workbuddy/memory/`（10-03、10-04 日志）。
- **未迁移**：`build/`(941M)、`.dart_tool/`(52M) —— 可再生，需要时跑一次 `flutter pub get` / 构建即可；正式校验走容器（持久 pub 缓存卷）。
- **.gitignore 追加** `_recon/`、`.workbuddy/`、`NEW-CHAT-PROMPT.md`，保证 `git status` 干净、现场资产不入库。
- **启动语** 已更新为：`接着做 SPlayer Mobile 项目：先读 F:\codex项目\播放器app\HANDOFF.md 顶部的「⚡ 启动包」，照它继续。`
- 迁移文档提交 `1bcb891` **已 push 到 origin/main**（本地与远端一致）。
- **旧目录 `C:\Users\47403\WorkBuddy\2026-10-03-23-40-41\` 已清理**：迁移前做过文件级核对（两侧各 119 个文件、零差异），确认新空间为唯一完整副本后，旧的 `build\`/`.dart_tool\` 缓存直接删除，其余源码树连同 `_recon\` 一并移入**回收站**（可恢复）。

### 2026-10-04 · v1.0.3 MissAV 播放不了 + 播放器补齐选集/竖滑/倍速

真机反馈（v1.0.2 整体通过）：① MissAV 能出详情但一点播就 `PlatformException(VideoError, unsupported URL, CoreMediaErrorDomain -1002)`；② 播放页缺「上下滑切集」「查看全部集随时切换」「倍速」。

**MissAV 根因（插件自己写明的）**：
```js
var MISSAV_PLAYER_MODE = "mpv";              // 插件顶部写死
// 注释原文：当显式指定 hls/system 时由服务端下发符合 Apple/FFmpeg 标准的 HLS master
```
`loadDetail` 里调 `buildSubtitleMasterUrl(...)` 时**漏传 playerType** → 走 `missavPlayerMode()` → `player=mpv` → 后端按 mpv 内核下发清单 → iOS 的 AVPlayer 直接 -1002。它是给 SPlayer（内置 mpv）写的。

**修法（两层，都不改组件源码）**：
1. **宿主播放内核声明**：`__capyApplyHostPlayerMode("hls")` —— 组件装载后，把名字匹配 `*PLAYER_MODE` 的全局字符串常量统一改成宿主真正支持的内核（本宿主是系统播放器）。
2. **播放候选链**：`lib/models/play_queue.dart` 的 `playUrlCandidates()` 把 `player=mpv` 改写为 `player=hls` 作为首选，原地址留作后备；播放器逐条尝试，全失败才报错。

**播放器补齐**（`lib/ui/player_page.dart` 重写）：
- 队列化：剧集=集、电影=线路，详情页把整条队列交给播放器；
- **上滑下一集 / 下滑上一集**（手势 + 顶部提示浮层）；
- **选集面板**（底部抽屉网格，随时跳集）；
- **倍速** 0.5x–2x；
- **线路切换**（含组件的 `playSources` 作为同集备用线路）+ 失败自动换源；
- 失败页可「重试 / 换线路 / 复制错误」。

新增测试：Node 契约测试加第 6 组（PLAYER_MODE 改写，5 项）；Dart 侧 6 条播放候选单测（含改写边界与 headers 透传）。

### 2026-10-04 · v1.0.2 修「参数编码少一层」（v1.0.1 引入的回归）

真机反馈（v1.0.1）：其他组件全报 `URL 非法：组件传入的是 null（null）`；黄果/MissAV 详情能出但「没有解析到可播放地址」；**原本能播的红果也坏了**。

**根因：桥接表达式的编码少了一层。**
- 宿主侧把参数发成 `__capyInvoke("c1","fn", {"page":1});` —— 第三个实参是 **JS 对象字面量**；
  JS 侧却执行 `JSON.parse(argJson)`，对对象只会得到 `"[object Object]"` → 抛错 → 参数静默变成 `{}`/`null`。
  正确姿势是**三层**：值 → `jsonEncode`（JSON 文本）→ `jsonEncode`（JS 字符串字面量）。
- 具体后果：
  1. 模块 `params` 一直是 `{}`（globalParams 的 serverUrl、分类的 category 全丢，组件只能靠自带默认值硬撑）；
  2. `loadDetail` 收到 `null` → 51吃瓜/帝果/黄豆/剧果/野果 直接把 null 丢给 `Widget.http.get` → 被 v1.0.1 新加的守卫拦下（`组件传入的是 null`）；
  3. 红果在 v1.0.0 能跑是因为当时传的是**对象**、且它有 `typeof link === "object"` 容错分支；v1.0.1 改成传字符串后，字符串因编码错误变成 null，`null && typeof null === 'object'` 走 falsy 分支 → `link.link` 取属性抛 TypeError → **红果反而坏了**（回归）；
  4. 黄果拿到 null 后走 `!detailUrl` 早退分支 → 返回"无可播地址"的合法对象 → 所以详情页有图有简介但没得播。
- 修法：抽出可测的 `buildInvokeExpression()`，统一做三层编码；`_run()` 所有调用走它。
- **防回归（这次的重点）**：新增 `tools/runtime-contract-test.mjs`，把**真实的 `capy_runtime.js`** 装进 Node 沙箱，
  用与 Dart 侧同构的表达式调用，断言「组件拿到的 params 是对象 / loadDetail 拿到的是字符串 / 非字符串 URL 被守卫拦住 / fetch 走原生通道」；
  并**故意跑一遍旧写法**证明它确实会把参数丢掉（1b 用例）。已接进 CI 的 analyze job。
  Dart 侧另有 3 条 `buildInvokeExpression` 单测（含引号/反斜杠转义与还原链）。

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
