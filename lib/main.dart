/// SPlayer Mobile —— clean-room 复刻的组件化播放器。
///
/// 运行时兼容 CapyPlayer / Forward Widget 规范：`WidgetMetadata` + 全局
/// `functionName` + `Widget.http` / `Widget.html` / `Widget.dom` + `loadDetail`。
library;

import 'package:flutter/material.dart';

import 'runtime/plugin_engine.dart';
import 'store/plugin_store.dart';
import 'ui/home_page.dart';
import 'ui/plugin_manager_page.dart';
import 'ui/search_page.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PluginStore.instance.load();
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

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const List<String> _titles = <String>['首页', '搜索', '插件', '设置'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_titles[_index], style: Theme.of(context).textTheme.headlineSmall),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: const <Widget>[
                      HomePage(),
                      SearchPage(),
                      PluginManagerPage(),
                      SettingsPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 运行时 WebView 宿主：挂在屏幕外，保证 JS 上下文一直存活
          IgnorePointer(
            child: ListenableBuilder(
              listenable: PluginEngine.instance,
              builder: (context, _) => PluginEngine.instance.buildHost(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: '搜索'),
          NavigationDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension), label: '插件'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
