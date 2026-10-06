/// 设置 / 关于。
library;

import 'package:flutter/material.dart';

import '../runtime/plugin_engine.dart';
import '../store/app_settings.dart';
import '../store/error_log.dart';
import '../store/history_store.dart';
import '../store/plugin_store.dart';
import '../store/update_service.dart';
import 'error_log_page.dart';
import 'history_page.dart';
import 'netlog_page.dart';
import 'update_flow.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    UpdateService.instance.currentVersion().then((value) {
      if (mounted) setState(() => _version = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        PluginStore.instance,
        PluginEngine.instance,
        HistoryStore.instance,
        AppSettings.instance,
        ErrorLog.instance,
      ]),
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
              leading: const Icon(Icons.system_update_alt),
              title: const Text('检查更新'),
              subtitle: const Text('从 GitHub Release 下载新版 APK 并调起安装器'),
              trailing: Text(_version.isEmpty ? '' : 'v$_version'),
              onTap: () => checkAndUpdate(context),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.update),
              title: const Text('启动时自动检查更新'),
              subtitle: const Text('只提示，不会自动安装'),
              value: AppSettings.instance.autoCheckUpdate,
              onChanged: (value) => AppSettings.instance.setAutoCheckUpdate(value),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.hub_outlined),
              title: const Text('播放兼容中转'),
              subtitle: const Text('分片改由本机转发（超时更宽、失败重试）。'
                  'Android 报「Source error」而 iOS 能播时打开它'),
              value: AppSettings.instance.hlsRelay,
              onChanged: (value) => AppSettings.instance.setHlsRelay(value),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('错误日志'),
              subtitle: const Text('闪退/异常记录，可一键复制发回排查'),
              trailing: Text('${ErrorLog.instance.count} 条'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ErrorLogPage()),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.playlist_play),
              title: const Text('自动连播下一集'),
              subtitle: const Text('一集播完自动接下一集（仅剧集生效）'),
              value: AppSettings.instance.autoPlayNext,
              onChanged: (value) => AppSettings.instance.setAutoPlayNext(value),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('观看历史'),
              subtitle: const Text('续播记录，可单条删除或一键清空'),
              trailing: Text('${HistoryStore.instance.count} 条'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HistoryPage(embedded: false)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('网络日志'),
              subtitle: const Text('组件请求了什么、返回了什么（排障用）'),
              trailing: Text('${PluginEngine.instance.allNetLogs().length} 条'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const NetLogPage()),
              ),
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
            ListTile(
              leading: const Icon(Icons.movie_filter_outlined),
              title: const Text('TMDB 中转地址'),
              subtitle: Text(
                AppSettings.instance.tmdbProxyBase.isEmpty
                    ? '未设置 · 留空时从组件来源地址自动推导'
                    : AppSettings.instance.tmdbProxyBase,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _editTmdbProxy(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('组件运行时能力', style: theme.textTheme.titleSmall),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '已实现：Widget.http(get/post/put/request)、Widget.html.load（jQuery 解析）、'
                'Widget.dom(parse/select/text/attr/remove)、Widget.storage、Widget.util.log、'
                'Widget.tmdb（经「TMDB 中转地址」，见上一项）\n'
                '每个组件独立 WebView，互不干扰。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('SPlayer Mobile'),
              subtitle: Text('组件运行时兼容 CapyPlayer / Forward Widget 规范\n'
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

  /// 编辑 TMDB 中转地址。
  ///
  /// 刻意**不接收 BuildContext 参数** —— 传参 context 在经过 await 之后使用会被
  /// `use_build_context_synchronously` 判为风险（本项目 `flutter analyze` 连 info
  /// 级 lint 都不放过）。统一用 State 自己的 `context` + `mounted` 守卫。
  Future<void> _editTmdbProxy() async {
    final controller = TextEditingController(text: AppSettings.instance.tmdbProxyBase);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('TMDB 中转地址'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'http://192.168.123.80:8788/ext/tmdb',
            helperText: '留空 = 从组件来源地址自动推导',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await AppSettings.instance.setTmdbProxyBase(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value.trim().isEmpty ? '已恢复自动推导' : '已保存 TMDB 中转地址'),
      ),
    );
  }
}
