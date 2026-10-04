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
> | 版本 | **v1.0.10 已发布**（修 v1.0.9 首页卡死）；上一版 v1.0.9 |
> | 技术栈 | Flutter 3.32.0 / Dart 3.8，单代码库出 Android + iOS |
> | 运行时 | 每个组件一个 WebView 沙箱；**装载并发上限 3（`BootGate`，名额直接交接）+ 75s 整体看门狗** |
> | 校验 | v1.0.10 容器内：`flutter analyze` **零问题**、Dart 单测 **62/62**；Node 契约 **17/17** |
> | 签名 | 4 个 GitHub Secrets 已配；**已实测 v1.0.9/v1.0.10 的 APK 证书指纹与本地 keystore 逐字一致** |
> | 发布说明 | ★ 唯一来源是 **`CHANGELOG.md`**；CI 自动抽取本版段落作为 Release 正文（v1.0.10 首次跑通） |
> | 网络 | ★ GitHub 走固定代理 `http://192.168.123.11:1061`；Release 资产用 `HTTPS_PROXY=… gh release download` |
> | 真机进度 | v1.0.4 分页 ✅、v1.0.5 三项 ✅；**v1.0.9 首页卡死 ❌（已修）**；v1.0.10 待复验 |
> | 底部导航 | 首页 / 搜索 / 历史 / 插件 / 设置（5 个标签） |
> | 现场资产 | 逆向产物都在 **`F:\codex项目\播放器app\_recon\`**（不在仓库里）：8 支组件源码 `widgets\*.js`、判定报告 `SPlayer_TV_1.8-组件兼容判定.md`、判定器 `apk_widget_compat.py`、沙箱 `widget_harness.mjs` |
> | 最后更新 | 2026-10-04 18:35（v1.0.9；已建 CHANGELOG.md 并回填 v1.0.0~v1.0.9 全部 Release 说明） |
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
> 1. **真机复测 v1.0.10**：导入组件后首页应正常出内容（v1.0.9 是全部转圈）。若仍失败，首页分区会显示**带「卡在哪一步」的错误横幅**，设置页「错误日志」也会有记录 —— 把那个发我即可精确定位。
> 2. **v1.0.9 的其它改动一并复验**：在线更新（设置页「检查更新」）、错误日志、全屏无提示条、闪退是否消失。
> 3. **v1.0.6/7/8 遗留**：进度记忆续播、历史页删除/清空、全屏与横竖屏、剧集自动连播。
> 4. MissAV 封面已放弃（后端无代理、CDN 客户端不可达）。
> 5. 待补能力：`Widget.tmdb`、`sectionMode`、字幕/弹幕面板、收藏夹、TV 大屏布局、跳过片头片尾。
>
> **④ 铁律（踩过的坑）**
> - **不要试图 1:1 反编译还原**：原 TV 版是 Kotlin+Compose 编译产物（78MB / 13 dex / R8 混淆），Compose 编译期变换不可逆。只做 clean-room（同规范、同模型、同能力）。
> - **验证 Flutter 必须挂持久 pub 缓存卷**：`docker run -v <proj>:/work -v flutter_pub:/root/.pub-cache ... ghcr.io/cirruslabs/flutter:3.32.0`；否则 `--rm` 一退就报 `Target of URI doesn't exist`、甚至 Flutter 自身 `Matrix4 isn't defined`（假故障）。
> - **Git Bash 里要先 `export MSYS_NO_PATHCONV=1`**，否则 `-w /work` 被转成 Windows 路径，docker 报 working directory invalid。
> - **`flutter analyze` 连 info 级 lint 都算失败**（`unnecessary_import`、`unintended_html_in_doc_comment`），必须清零。
> - ★ **「GitHub 没更新」先分清是 commit 还是 Release**：推 `main` 只更新代码与 Actions 产物（Artifacts）；**Releases 页面只在推 `v*` tag 时才生成**（workflow 的 `release` job 条件是 `startsWith(github.ref, 'refs/tags/v')`）。要出 Release 就 `git tag -a vX.Y.Z && git push origin vX.Y.Z`。
> - ★★ **`ScrollController` 必须真的挂到滚动组件上**：`_ModuleList` 建了控制器并 `addListener`，但 `PosterGrid` 当时没有 `controller` 参数 → 监听永不触发 → **每个组件只加载第 1 页**（真机现象：下滑不加载后续资源）。凡是「滚到底加载更多」，务必确认控制器确实挂在同一个可滚动组件上，并用 widget 测试断言 `controller.hasClients == true`。
> - **分页要防「后端不认 page」**：判断是否还有更多不能只看 `items.isNotEmpty`（后端每页返回同一批会无限重复追加）；按 id/标题去重后新增数为 0 就视为到底。统一走 `mergePage()`（`lib/models/paging.dart`）。
> - ★★ **懒加载列表里的分区必须保活**：`ListView` 的 child 滚出视口会被销毁，State 没了 → `initState` 重新拉网络 → 用户看到「滑回来又加载一遍」。用 `AutomaticKeepAliveClientMixin`（`wantKeepAlive => true` + `super.build(context)`）**加**一层首屏缓存（`_homeSectionCache`，只有下拉刷新才清）。
> - ★★ **全屏手势层会抢进度条**：播放页原本用 `GestureDetector(onVerticalDragEnd:)` 包住整屏，进度条（`VideoProgressIndicator`）轨道只有几像素、命中区太窄，横拖经常抢不过手势 → 「拖不动」。正解是**手势层只包视频区**，控制条放在它外面，并用自带 ~48dp 命中高度的 `Slider`。
> - ★ **方向锁 / 沉浸式是全局状态，退出播放页必须还原**：`SystemChrome.setPreferredOrientations(const [])` 放开方向、`setEnabledSystemUIMode(edgeToEdge)` 把状态栏还回来。否则回到首页还卡在横屏、状态栏也没了。还原写在播放页 `dispose()` 里。
> - **自适应只用一处断点常量**：`lib/ui/layout.dart` —— `kRailBreakpoint = 600`（宽 ≥ 600dp 用左侧导航栏）+ `posterRowHeight/posterCardWidth`（海报行随可用高度收缩到 150~210）。别在各页面各写一套魔法数字。
> - ★ **自动连播只在「剧集」模式生效**：`PlayerPage.episodes` 是统一队列 —— 剧集是「集」，电影是「多个线路」。自动跳对后者等于**换线路**，是错的。判定统一走 `shouldAutoAdvance()`（`lib/models/play_queue.dart`），并由详情页传 `episodeList: true/false`。
> - **播完判定要防重入**：`_onTick` 每帧都跑，靠 `_completionHandled` 一次性标记；`_load()` 里必须把它重置回 false，否则切下一集后不会再触发。
> - ★★ **启动失败的运行实例必须立刻从池子里摘掉并 `dispose()`**：旧 `runtimeFor` 会在覆盖 `_runtimes[id]` 时**不释放旧实例** → 每次重试都多留一个 WebView（泄漏 → 内存持续上涨 → 闪退）。同时 `runtimeIfReady` 名字叫 ready 却从不检查 `isBooted`。
> - ★★ **WebView 启动要限流**：8 支组件一起 `boot()` 时，低端机会「运行时初始化超时」甚至被系统杀进程（对应反馈里的「组件未加载」）。`PluginEngine.maxConcurrentBoots = 3` 排队启动；`boot()` 外壳就绪阶段 30s × 2 次重试（组件源码注入阶段不重试，那是组件自身的问题）。
> - **release 包异常是静默的**：必须装 `ErrorLog.install()`（`FlutterError.onError` + `PlatformDispatcher.onError`）落盘到 `<appDocs>/error.log`，设置页可一键复制 —— 否则用户只能说「闪退」，拿不到堆栈。
> - ★ **换了签名 key 就必须卸载重装一次**：debug key → release key 属于不同签名，系统直接拒绝覆盖安装。**keystore 丢了就永久失去覆盖升级能力**，务必多处备份。
> - ★★ **凡是「可能永不返回」的 await，都必须有超时兜底**：`WebView` 的 `loadHtmlString` / `runJavaScript` 在平台视图未挂载时会**永不返回** —— 一旦它被放在锁/闸门里，就会把整个闸门拖死（v1.0.9 首页全部转圈、还没日志就是这么来的）。所有这类调用都加 `.timeout()`，并在外层再加一个整体看门狗。
> - ★★ **并发闸门别用轮询实现**：`while (used >= max) await Future.delayed(...)` 在「持票者永不归还」时会假死。正解是**名额直接交接**（`release()` 时唤醒队首、计数不变），见 `lib/runtime/boot_gate.dart` + 它的单测。
> - **WebView 调用前先确认已挂到界面树**：`await SchedulerBinding.instance.endOfFrame`（等一帧）之后再 `loadHtmlString`。
> - ★★ **每次发版前先在 `CHANGELOG.md` 补一段 `## vX.Y.Z`**：CI 的 `release` job 会取该段作为 Release 正文（取不到会打印「未在 CHANGELOG.md 写说明」）。段尾的分隔线与空行会被自动裁掉。
> - **发版流程固定为三步**：① `pubspec.yaml` 升版本 ② `CHANGELOG.md` 补该版本段落 ③ `git tag -a vX.Y.Z && git push origin vX.Y.Z`。
> - **仓库是公开的**：README/HANDOFF/CHANGELOG 都会公开。用户 2026-10-04 已把 README 里「复刻 / 反编译」相关措辞删掉 —— 对外文案（CHANGELOG、Release 说明）一律只写产品能力，不要提逆向。
> - ★★ **封面图要带浏览器 UA**：`CachedNetworkImage` 默认发 Dart 的 UA，封面 CDN 会挡。统一走 `lib/ui/poster_image.dart`（UA + `Accept: image/*`；失败再带 Referer 重试一次，优先用 `WidgetRuntime.imageReferer` —— 即组件自己请求站点时用的那个 Referer）。
> - **MissAV 封面没有后端图片代理**：provider 类组件（51吃瓜/帝果/黄豆/剧果/野果/黄果）的封面由后端**代理好**（`/api/v1/providers/{id}/cover?url=…`，实测 200）；MissAV 只有 `/api/v1/missav/cover-probe`（只返回解析后的 CDN 直链，不代理），客户端必须自己能连上 `fourhoi.com` / `spic2-*.71352.men`。连不上就是网络/内容源侧的问题。
> - **观看历史的粒度是「媒体 × 剧集」**：`watchEpisodeKey(target, 剧集标题)`；媒体级 key = `pluginId::mediaId`（同一部剧的「继续观看」靠它找最近一条）。记录存在 `<appDocs>/history.json`，上限 500 条，超了丢最旧的。
> - **`dispose()` 里存进度要同步读值**：`VideoPlayerController` 一 `dispose` 就拿不到 `value` 了 —— 必须在 dispose 里**先同步读出** position/duration，再 `unawaited` 落盘，最后才 `controller.dispose()`。
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

### 2026-10-04 · v1.0.10 修 v1.0.9 首页全部卡死（我自己的回归）

**现象**：v1.0.9 装好后首页每个分区一直转圈、加载不出来，**且没有任何错误日志**。

**根因（v1.0.9 引入）**：我把「同时启动上限 3」用
`while (_bootingCount >= 3) await Future.delayed(100ms);` **轮询**实现，
而 `boot()` 里的 `await _controller.loadHtmlString(...)` **没有超时** ——
WebView 还没挂到界面树时这个 await 可能**永不返回** → `finally` 里的
`_bootingCount--` 永远不执行 → **名额永不释放 → 后续组件全部排队假死**。
既不成功也不失败，所以「没错误日志」。**限流的方向没错，实现方式错了。**

**修法（让它可证明不会卡死）**：
1. 抽出 **`lib/runtime/boot_gate.dart`**：并发闸门，`release()` 时**名额直接交接给队首**
   （不轮询、不丢名额），并配 `test/boot_gate_test.dart` 4 条回归测试锁住这类 bug。
2. `boot()` 加载前先 `await SchedulerBinding.instance.endOfFrame` ×2 —— **确保 WebView 已挂上界面树**。
3. `loadHtmlString` / `_shellReady` / `runJavaScript` / `runJavaScriptReturningResult` **全部加 20s 超时**。
4. `_stage` 记录当前步骤，引擎加 **75s 整体看门狗**：超时抛
   「组件「X」装载超时（卡在：<步骤>）」并写进 `ErrorLog` —— 首页错误横幅 + 错误日志双通道可见。
5. 恢复 20s 单次超时（v1.0.9 改成 30s×2 次重试，让失败要等 60 秒才出现，更像假死）。
6. 保留 v1.0.9 的正确改动：启动失败/被覆盖的实例一律 `dispose()`（防 WebView 泄漏）。

**教训（写进铁律）**：凡是**可能永不返回**的 await 都必须有超时兜底；并发闸门不要用轮询实现。

版本 `1.0.9+10` → `1.0.10+11`。验证：容器 analyze 零问题、Dart **62/62**。
**已发布 Release `v1.0.10`**（CI run `37194915372` 四 job 全绿；APK sha256 `be224f23…8a98`、
证书指纹与 v1.0.9 同一把 release key）。**这是第一次由 CHANGELOG.md 自动生成 Release 正文的版本，跑通。**

### 2026-10-04 · 补历史版本的更新说明（CHANGELOG + Release 自动带说明）

用户要求：**之前所有版本都要写更新内容**。

**问题**：此前每个 Release 的正文都只有一行自动生成的
`**Full Changelog**: .../compare/...`（93 字符），没有任何实际说明 —— 因为 workflow 用了
`generate_release_notes: true`，而仓库一直是直接 push 到 main、没有 PR/issue，自动生成自然没内容。

**做法**：
1. 新增 **`CHANGELOG.md`**（发布说明的**唯一来源**），按 `## vX.Y.Z` 分段，补写 v1.0.0 → v1.0.9 全部十版。
   文案只写产品能力，**不提逆向/复刻**（用户已把 README 里这类措辞删掉）。
2. **回填全部历史 Release**：脚本从 CHANGELOG 取对应段落 → 裁掉段尾 `---`/空行 → 追加
   「完整变更对比」链接（用 `git describe --tags --abbrev=0 <tag>^` 算上一版）+ 安装包说明 →
   `gh release edit <tag> --notes-file`。**10/10 成功**。
3. **让以后自动带上**：改 `build.yml` 的 `release` job —— 加 `actions/checkout`（`fetch-depth: 0`，为了算上一版），
   新增「生成本次发布说明」步骤（同样的 awk 抽取 + 裁尾），`action-gh-release` 改用 `body_path: release-notes.md`
   并去掉 `generate_release_notes`。

**新发版流程**：① `pubspec.yaml` 升版本 → ② `CHANGELOG.md` 补 `## vX.Y.Z` 段 → ③ `git tag -a vX.Y.Z && git push origin vX.Y.Z`。

### 2026-10-04 · v1.0.9 Android 在线更新 + 正式签名 + 装载健壮性 + 错误日志

用户：① 全屏底部那条「点屏幕呼出控制条」提示碍事（挡住字幕），去掉；② 做 Android 在线更新，并解决签名问题；③ 安卓退出后再进会闪退；④ 部分用户提示「组件未加载」。

**① 去掉全屏提示** —— 删掉 `player_page.dart` 里 `!_controlsVisible` 时那条 `Positioned` 文字即可（全屏控制条仍是点屏幕呼出/收起）。

**② 在线更新 + 签名（关键）**
- **先解决签名**，否则更新包根本装不上去：仓库此前**没有配任何 secrets**，CI 一直在用**临时 debug 签名**（每次跑出来的 key 都可能不同 / 上游镜像一换就变）。
- 生成 release keystore（`keytool`，RSA2048 / 有效期 10000 天 / alias `splayer`），落盘在 **`.signing/`**（已加 gitignore），并把 4 个 GitHub Secrets 配好：`ANDROID_KEYSTORE_BASE64` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD` / `ANDROID_STORE_PASSWORD`。
- ⚠️ **换 key 后必须卸载重装一次**（签名不一致系统会拒绝覆盖安装）；`.signing/` 丢了就永久失去覆盖升级能力，务必备份。
- 新增 `lib/store/update_service.dart`：查 `releases/latest` → 比对版本（数字比较，`1.0.10 > 1.0.9`）→ 下载 APK。**下载优先走 `api.github.com` 的资产接口**（`/releases/assets/{id}` + `Accept: application/octet-stream`）—— 实测本机对 `github.com` 主站时断时续，浏览器下载地址经常 000。
- 新增 `lib/ui/update_flow.dart`：说明弹窗（版本/大小/更新内容）→ 带百分比的下载弹窗 → `OpenFilex.open()` 调起系统安装器。
- 设置页加「检查更新」（显示当前版本）+「启动时自动检查更新」开关；启动后延迟 4 秒静默检查（避免和首屏 WebView 抢资源）。Manifest 加 `REQUEST_INSTALL_PACKAGES`。

**③④ 闪退 / 组件未加载 —— 两个真 bug**
- **WebView 泄漏**：`runtimeFor` 在启动失败后会把旧实例留在 `_runtimes` 里，**再次调用时直接覆盖且不 dispose** → 每次重试多留一个 WebView → 内存持续上涨 → 闪退。现在失败即「摘掉 + dispose」，覆盖前也先释放旧实例。
- **同时启动太多**：8 支组件一起 `boot()`，低端机必然超时或被系统杀。新增 `PluginEngine.maxConcurrentBoots = 3` 排队启动。
- `boot()` 拆成两阶段：外壳就绪（受设备性能影响）**30s × 2 次重试**；组件源码注入阶段失败不重试（那是组件自身问题）。
- `runtimeIfReady` 名字叫 ready 却从不检查 `isBooted` → 已修正（避免拿到未装载的实例后报「组件未装载」）。
- 报错文案改为可行动：「组件「X」尚未装载完成，请稍后重试」。
- **新增错误日志**：`lib/store/error_log.dart`（`FlutterError.onError` + `PlatformDispatcher.onError` → `<appDocs>/error.log`）+ `lib/ui/error_log_page.dart`（一键复制/清空），设置页入口。release 包异常本来静默，有了它才能定位闪退。

**新增测试** `test/update_test.dart`（7 条：版本解析与数字比较）。版本 `1.0.8+9` → `1.0.9+10`。
验证：容器 analyze 零问题、Dart **58/58**、Node 契约 **17/17**。

**已发布 Release `v1.0.9`**（tag 指向 `319bc2d`，CI run `37192811720` 四 job 全绿）
<https://github.com/chenweitian423/splayer-mobile/releases/tag/v1.0.9>
- `SPlayerMobile-v1.0.9-android.apk` 55.7 MB sha256 `a6f587be…df79`
- `SPlayerMobile-v1.0.9-ios-unsigned.ipa` 23.8 MB sha256 `a074a0ff…d0295`

**签名自证（已实测）**：CI 日志出现「已使用仓库 secrets 中的正式签名」；APK 证书指纹
`SHA1 77:E1:89:F8:A5:74:75:C9:29:68:FB:78:1D:8B:D6:2E:08:73:AC:4F` /
`SHA256 5A:C6:18:BD:3E:B1:4E:0A:A3:5F:90:5A:83:6A:9E:50:95:26:D1:3E:20:4C:58:58:5D:16:C3:E6:0C:12:1C:9B`
与 `.signing/upload-keystore.jks` 的证书**逐字一致** —— 覆盖升级链路成立。

本地产物：`F:\codex项目\播放器app\build\release\v1.0.9\`（sha256 已核对）。
> ⚠️ **签名材料 `.signing/` 务必多地备份**；丢了就永久失去「在线更新覆盖安装」的能力。
> 网络：GitHub 走固定代理 **`http://192.168.123.11:1061`**；Release 资产用
> `HTTPS_PROXY=... gh release download <tag> -D <dir> --clobber` 最快（curl 经代理会 502）。

### 2026-10-04 · v1.0.8 剧集自动连播

用户反馈：v1.0.5 三项（分区保活/进度条/封面图）真机通过；MissAV 封面仍不行，**暂时放弃**（已确认后端无代理、CDN 客户端不可达）；新增需求「剧集自动播放下一集」。

**关键设计：先分清「剧集」和「线路」**。`PlayerPage.episodes` 是统一队列 —— 剧集模式下是「第 N 集」，电影模式下是「同一部片的多个线路」。对后者自动跳等于**换线路**，不是连播。所以：
- 详情页新增 `_isEpisodeMode`（`detail.allEpisodes.isNotEmpty`），以 `episodeList` 传给播放页。
- 判定收敛成纯函数 `shouldAutoAdvance(currentIndex, total, enabled, episodeList)`（`lib/models/play_queue.dart`），4 个条件缺一不可。

**实现**：
- 新增 `lib/store/app_settings.dart`：`autoPlayNext`（默认开），落盘 shared_preferences，`main()` 里 `load()`。
- `player_page.dart`：`_onTick` 里判「位置贴到时长且已停」→ `_handleCompletion()`：先把 position 按总时长写入历史（= 记「已看完」），再按 `shouldAutoAdvance` 决定切下一集（飘提示「自动播放下一集：xxx」）或停住（最后一集提示「已经是最后一集」）。`_completionHandled` 防重入，`_load()` 里重置。
- 底栏 + 全屏悬浮行加 `playlist_play` 一键开关（仅剧集模式显示）；设置页加 `SwitchListTile`。

**新增测试** `test/autoplay_test.dart`（5 条）：正常连播、最后一集不连播、开关关掉不连播、非剧集模式不连播、单条/0 条不连播。

版本 `1.0.7+8` → `1.0.8+9`。验证：容器 analyze 零问题、Dart **51/51**、Node 契约 **17/17**。

**已发布 Release `v1.0.8`**（tag 指向 `f1b7445`，CI run `37189101835` 四 job 全绿）
<https://github.com/chenweitian423/splayer-mobile/releases/tag/v1.0.8>
- `SPlayerMobile-v1.0.8-android.apk` 55.5 MB sha256 `977edb20…5c40`
- `SPlayerMobile-v1.0.8-ios-unsigned.ipa` 23.7 MB sha256 `a338a3c5…f100`

本地产物：`F:\codex项目\播放器app\build\release\v1.0.8\`（APK 已核对 sha256 一致；IPA 因 `github.com` 主站当时不可达未落地，需要时从 Release 页直接下）。
> 网络备注：本机对 `github.com` 时有不可达，`releases/download/...` 会失败；**`api.github.com` 通常可达**，可用 `gh api repos/<owner>/<repo>/releases/assets/<id> -H "Accept: application/octet-stream" > <file>` 兜底下载。

### 2026-10-04 · v1.0.7 屏幕自适应 + 播放器全屏 / 横竖屏切换

用户要：屏幕自适应、横竖向切换按钮、全屏按钮。

**平台侧先确认**：Android `AndroidManifest` 没锁 `screenOrientation`（且 `configChanges` 已含 orientation/screenSize），iOS `Info.plist` 支持竖屏 + 两个横屏 —— 所以**旋转本来就能用**，缺的是布局自适应与播放入口的按钮。

**① 自适应（新增 `lib/ui/layout.dart`，纯函数可测）**
- `kRailBreakpoint = 600`：宽 ≥ 600dp（横屏 / 平板）时 `main.dart` 把底部 `NavigationBar` 换成左侧 `NavigationRail`，避免横屏时底部那条挤掉内容高度；内容加 `kContentMaxWidth = 1100` 限宽，超宽屏不把海报拉变形。
- `posterRowHeight(可用高度)` → `(h * 0.34).clamp(150, 210)`：横屏矮屏时首页海报行自动变矮（原来写死 208，横屏占掉大半屏）。
- `posterCardWidth(行高)`、`posterGridExtent(宽度)`：卡片与网格边长跟着走。

**② 播放页 `player_page.dart`**
- 新增状态 `_fullscreen` / `_landscape` / `_controlsVisible` + 自动隐藏 `Timer`。
- **全屏按钮**：隐藏 AppBar 与底部操作条、`SystemUiMode.immersiveSticky` 隐藏系统栏、默认转横屏；控制层改成浮在视频上的半透明渐变条；点视频区呼出/收起，5 秒无操作自动隐藏。
- **横竖屏按钮**：只切方向、不动界面（AppBar 右上 + 全屏时的悬浮行里都有）。图标随当前方向变（横屏时显示"切换为竖屏"）。
- 全屏悬浮行还带「选集 / 线路 / 倍速」（原来这些在底部栏，全屏时被隐藏了）。
- **退出还原**：`dispose()` 里放开方向锁 + `edgeToEnd` 恢复系统栏。

**新增测试** `test/layout_test.dart`（7 条）：导航断点、横竖判定、行高上下限与线性区间、卡片宽度夹取、网格边长。

版本 `1.0.6+7` → `1.0.7+8`。验证：容器 analyze 零问题、Dart **46/46**、Node 契约 **17/17**。

**已发布 Release `v1.0.7`**（tag 指向 `ba93690`，CI run `37186828001` 四 job 全绿）
<https://github.com/chenweitian423/splayer-mobile/releases/tag/v1.0.7>
- `SPlayerMobile-v1.0.7-android.apk` 55.5 MB sha256 `2940eb24…784c`
- `SPlayerMobile-v1.0.7-ios-unsigned.ipa` 23.7 MB sha256 `493abb59…9270`

本地产物：`F:\codex项目\播放器app\build\release\v1.0.7\`（sha256 已与 Release 核对一致）。

### 2026-10-04 · v1.0.6 播放进度记忆 + 观看历史

用户要「播放进度记忆，也就是历史记录，能清理」。

**新增 `lib/store/history_store.dart`**：
- `WatchTarget`（插件 id + 媒体 id + 标题/封面/详情链接）→ `mediaKey = pluginId::mediaId`。
- `WatchRecord`：`key`（`媒体key::剧集标题`，无剧集则退化为媒体 key）、`positionMs`/`durationMs`/`updatedAt`；派生 `progress`（0~1）、`finished`（≥98%）、`resumable`（≥5s 且未完）。
- `HistoryStore`（ChangeNotifier）：落盘 `<appDocs>/history.json`，上限 500 条（超出丢最旧），`find/latestForMedia/save/remove/clear`。位置没变不重复写盘。

**新增 `lib/ui/history_page.dart`**：封面 + 标题 + 剧集 + 进度条 + 相对时间；**左滑删除单条**、右侧 ✕ 删除、右上「清空」（带二次确认）；点击回到该条目的详情页（用 `PluginEngine.runtimeFor` 重建运行时），组件被删/停用会给出明确提示；空态有引导文案。

**播放页 `player_page.dart`**：新增 `WatchTarget target` 与 `fromStart`；`initialize()` 之后按记录 `seekTo` 续播并提示「已从 mm:ss 继续播放」；每 5 秒落一次盘、切集前落一次、`dispose()` 里同步读值后落一次。`fromStart` 时把记录清零。

**详情页 `detail_page.dart`**：新增 `WatchTarget _target`；有可续播记录时主按钮变「**继续观看 · mm:ss**」并多一个「从头播放」副按钮；从播放页返回时 `setState` 刷新按钮。

**导航**：底部加 **历史** 标签（首页 / 搜索 / 历史 / 插件 / 设置）；设置页也加一条「观看历史」入口（显示条数）。启动时 `HistoryStore.load()`。

**新增测试** `test/history_test.dart`（7 条）：剧集 key 生成、progress 夹取、98% 判定、<5s 不续播、JSON 往返、缺字段容错。

版本 `1.0.5+6` → `1.0.6+7`。验证：容器 analyze 零问题、Dart **39/39**、Node 契约 **17/17**。

**已发布 Release `v1.0.6`**（tag 指向 `4faef71`，CI run `37185488375` 四 job 全绿）
<https://github.com/chenweitian423/splayer-mobile/releases/tag/v1.0.6>
- `SPlayerMobile-v1.0.6-android.apk` 55.4 MB sha256 `191ddae0…47f8`
- `SPlayerMobile-v1.0.6-ios-unsigned.ipa` 23.7 MB sha256 `17488214…b712`

本地产物：`F:\codex项目\播放器app\build\release\v1.0.6\`（sha256 已与 Release 核对一致）。

### 2026-10-04 · v1.0.5 首页保活 / 进度条可拖 / 封面图请求头 / MissAV 链路核对

用户真机反馈三件事 + 要求顺手核掉 v1.0.3 遗留的 MissAV 播放。

**① 首页「滑下去/滑回来都重新加载」**（不合理）
根因：首页 `ListView` 的每个分区（`_PluginSection`）滚出视口就被销毁，State 没了 → 重新 `initState` → 再打一次网络。
修法：`_PluginSectionState` 加 `AutomaticKeepAliveClientMixin`（`wantKeepAlive = true`）+ 一层首屏缓存 `_homeSectionCache`（key = recordId），命中缓存直接秒出、**不再请求**；只有下拉刷新（`clearHomeSectionCache()`）才重新拉。

**② 播放页进度条拖不动**
根因：`GestureDetector(onVerticalDragEnd:)` 包住了**整屏**，而进度条用的是 `VideoProgressIndicator` —— 轨道只有几像素、命中区太窄，横向拖拽经常抢不过整屏的垂直手势。
修法：**手势层只包视频区**（`Expanded` 里的 GestureDetector），控制条移到它外面；进度条换成自带 ~48dp 命中高度的 `Slider`（`_Scrubber`，拖拽中显示目标位置、松手才 `seekTo`），并补了缓冲指示与播放/暂停 tooltip。

**③ MissAV 封面 99% 加载不出来**
根因（实测）：封面是**客户端直连 CDN**，`CachedNetworkImage` 发的是 Dart 默认 UA、也不带 Referer，CDN 一律挡；另外 `fourhoi.com` 在部分网络下**根本不可达**（本机 curl = SSL 失败），`spic2-*.71352.men` 返回 403。
修法：新增 `lib/ui/poster_image.dart` —— 统一带浏览器 UA + `Accept: image/*` 请求，失败再带 Referer 重试一次（优先用组件自己请求站点时用的 Referer：`WidgetRuntime.imageReferer`，没有则退化为图片同源地址）。全部封面位（首页行 / 分类网格 / 搜索 / 详情）都切到它。

**④ MissAV 播放链路核对**（后端实测）
- 路由**已恢复**：`/api/v1/discovery/sites/missav/routes` → `www.missav08.com`（`x99-direct`）。v1.0.1 那个「Runtime 无线路」已不复现。
- `/api/v1/subtitles/master.m3u8`、`/api/v1/missav/{prepare,playlists,cover-probe}` 都在（后端 OpenAPI 52 条路径已导出核对）。
- 宿主侧 `var MISSAV_PLAYER_MODE = "mpv"` 是**顶层 `var`**，会成为 `window` 属性 → `__capyApplyHostPlayerMode("hls")` 能改掉，`player=hls` 链路成立。
- **修正**：详情页直接用「详情」的 `playerType`（MissAV 列表项给 `none`、详情才给 `system`）—— 新增 `CapyDetail.playerType` 解析。

**新增测试** `test/poster_image_test.dart`（5 条：3 条请求头 + 2 条 `CapyDetail.playerType`）。版本 `1.0.4+5` → `1.0.5+6`。
验证：容器 `flutter analyze` 零问题、Dart **32/32**、Node 契约 **17/17**。

**已发布 Release `v1.0.5`**（tag 指向 `77ac9e2`，CI run `37184337514` 四 job 全绿）
<https://github.com/chenweitian423/splayer-mobile/releases/tag/v1.0.5>
- `SPlayerMobile-v1.0.5-android.apk` 55.2 MB sha256 `78c900fd…80ec9`
- `SPlayerMobile-v1.0.5-ios-unsigned.ipa` 23.7 MB sha256 `40eda7ef…b6900a`

本地产物：`F:\codex项目\播放器app\build\release\v1.0.5\`（sha256 已与 Release 核对一致）。

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
