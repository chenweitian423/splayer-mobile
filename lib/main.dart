/// SPlayer Mobile —— clean-room 复刻的组件化播放器。
///
/// 运行时兼容 CapyPlayer / Forward Widget 规范：`WidgetMetadata` + 全局
/// `functionName` + `Widget.http` / `Widget.html` / `Widget.dom` + `loadDetail`。
library;

import 'package:flutter/material.dart';

import 'runtime/plugin_engine.dart';
import 'store/app_settings.dart';
import 'store/history_store.dart';
import 'store/plugin_store.dart';
import 'ui/history_page.dart';
import 'ui/home_page.dart';
import 'ui/layout.dart';
import 'ui/plugin_manager_page.dart';
import 'ui/search_page.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PluginStore.instance.load();
  await HistoryStore.instance.load();
  await AppSettings.instance.load();
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
