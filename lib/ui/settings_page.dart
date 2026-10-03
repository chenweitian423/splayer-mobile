/// 设置 / 关于。
library;

import 'package:flutter/material.dart';

import '../runtime/plugin_engine.dart';
import '../store/plugin_store.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[PluginStore.instance, PluginEngine.instance]),
      builder: (context, _) {
        final records = PluginStore.instance.records;
        final loaded = records.where((r) => PluginEngine.instance.isReady(r.id)).length;
        return ListView(
          children: <Widget>[
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('已安装组件'),
              trailing: Text('${records.length} 个（已装载 $loaded）'),
            ),
            ListTile(
              leading: const Icon(Icons.cached),
              title: const Text('卸载全部运行时'),
              subtitle: const Text('释放 WebView 与 JS 上下文'),
              onTap: () {
                for (final record in records) {
                  PluginEngine.instance.drop(record.id);
                }
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已卸载全部运行时')));
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('组件运行时能力', style: theme.textTheme.titleSmall),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '已实现：Widget.http(get/post/put/request)、Widget.html.load（jQuery 解析）、'
                'Widget.dom(parse/select/text/attr/remove)、Widget.storage、Widget.util.log\n'
                '未实现：Widget.tmdb（需要 TMDB API Key）\n'
                '每个组件独立 WebView，互不干扰。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('SPlayer Mobile'),
              subtitle: Text('clean-room 复刻 · 组件运行时兼容 CapyPlayer / Forward Widget 规范\n'
                  '本应用只提供播放器与运行时，不内置、不提供任何内容源。'),
              isThreeLine: true,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Text(
                '导入组件前请自行确认来源合法可信；组件会以脚本形式在应用内运行。',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
}
