/// SPlayer Mobile —— 组件化播放器。
///
/// 运行时兼容 CapyPlayer / Forward Widget 规范：`WidgetMetadata` + 全局
/// `functionName` + `Widget.http` / `Widget.html` / `Widget.dom` + `loadDetail`。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'runtime/deep_link.dart';
import 'runtime/plugin_engine.dart';
import 'store/app_settings.dart';
import 'store/error_log.dart';
import 'store/history_store.dart';
import 'store/plugin_store.dart';
import 'ui/history_page.dart';
import 'ui/home_page.dart';
import 'ui/layout.dart';
import 'ui/plugin_manager_page.dart';
import 'ui/search_page.dart';
import 'ui/settings_page.dart';
import 'ui/update_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 先把错误钩子装上：后面任何初始化异常都能被记下来。
  ErrorLog.instance.install();
  await ErrorLog.instance.load();
  await PluginStore.instance.load();
  await HistoryStore.instance.load();
  await AppSettings.instance.load();
  // 深链通道要在首帧之前装好，否则冷启动带进来的链接会丢。
  await DeepLinkService.install();
  runApp(const SPlayerApp());
}

class SPlayerApp extends StatelessWidget {
  const SPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPlayer Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const List<_Dest> _destinations = <_Dest>[
    _Dest(Icons.home_outlined, Icons.home, '首页'),
    _Dest(Icons.search_outlined, Icons.search, '搜索'),
    _Dest(Icons.history_outlined, Icons.history, '历史'),
    _Dest(Icons.extension_outlined, Icons.extension, '插件'),
    _Dest(Icons.settings_outlined, Icons.settings, '设置'),
  ];

  void _select(int value) => setState(() => _index = value);

  @override
  void initState() {
    super.initState();
    DeepLinkService.pending.addListener(_onDeepLink);
    // 启动后延一会儿再查更新：别和首屏那批 WebView 抢资源。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_autoCheckUpdate());
      // 冷启动带进来的安装链接，这时才有 ScaffoldMessenger 可用。
      unawaited(_onDeepLink());
    });
  }

  @override
  void dispose() {
    DeepLinkService.pending.removeListener(_onDeepLink);
    super.dispose();
  }

  /// 收到 `xxx://add-widget?data=…`（托管页的「安装」按钮）→ 直接装组件。
  Future<void> _onDeepLink() async {
    final link = DeepLinkService.pending.value;
    if (link == null || link.isEmpty) return;
    DeepLinkService.consume();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final record = await PluginStore.instance.importFromUrl(link);
      if (!mounted) return;
      // 切到「插件」页，让用户看见装了什么，而不是毫无反应。
      setState(() => _index = 3);
      messenger.showSnackBar(SnackBar(content: Text('已安装组件：${record.title} v${record.version}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('安装失败：$e')));
    }
  }

  Future<void> _autoCheckUpdate() async {
    if (!AppSettings.instance.autoCheckUpdate) return;
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    await checkAndUpdate(context, silent: true);
  }

  @override
  Widget build(BuildContext context) {
    // 宽屏（横屏 / 平板）用左侧导航栏，窄屏用底部导航栏 —— 不然横屏时底部那条会挤掉内容高度。
    final useRail = useNavigationRail(MediaQuery.sizeOf(context).width);

    // IndexedStack 的 index 不能是常量，单独构造一次。
    final pages = IndexedStack(
      index: _index,
      children: const <Widget>[
        HomePage(),
        SearchPage(),
        HistoryPage(),
        PluginManagerPage(),
        SettingsPage(),
      ],
    );

    final title = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(_destinations[_index].label, style: Theme.of(context).textTheme.headlineSmall),
      ),
    );

    final body = useRail
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                labelType: NavigationRailLabelType.all,
                destinations: <NavigationRailDestination>[
                  for (final dest in _destinations)
                    NavigationRailDestination(
                      icon: Icon(dest.icon),
                      selectedIcon: Icon(dest.selectedIcon),
                      label: Text(dest.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                    child: Column(children: <Widget>[title, Expanded(child: pages)]),
                  ),
                ),
              ),
            ],
          )
        : Column(children: <Widget>[title, Expanded(child: pages)]);
    return Scaffold(
      body: Stack(
        children: <Widget>[
          SafeArea(child: body),
          // 运行时 WebView 宿主：挂在屏幕外，保证 JS 上下文一直存活
          IgnorePointer(
            child: ListenableBuilder(
              listenable: PluginEngine.instance,
              builder: (context, _) => PluginEngine.instance.buildHost(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: <NavigationDestination>[
                for (final dest in _destinations)
                  NavigationDestination(icon: Icon(dest.icon), selectedIcon: Icon(dest.selectedIcon), label: dest.label),
              ],
            ),
    );
  }
}
