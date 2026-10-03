/// 网络日志：组件发出的每个请求 + 返回状态，用于在没有真机调试器时定位问题。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../runtime/plugin_engine.dart';

class NetLogPage extends StatelessWidget {
  const NetLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: PluginEngine.instance,
      builder: (context, _) {
        final logs = PluginEngine.instance.allNetLogs();
        final text = logs.map((log) => log.line).join('\n\n');
        return Scaffold(
          appBar: AppBar(
            title: Text('网络日志（${logs.length}）'),
            actions: <Widget>[
              IconButton(
                tooltip: '复制全部',
                icon: const Icon(Icons.copy_all),
                onPressed: logs.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制，直接发我即可')),
                        );
                      },
              ),
              IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.delete_outline),
                onPressed: logs.isEmpty ? null : PluginEngine.instance.clearNetLogs,
              ),
            ],
          ),
          body: logs.isEmpty
              ? const Center(child: Text('还没有请求记录，去首页刷一下再看'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final colour = log.ok ? theme.colorScheme.primary : theme.colorScheme.error;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${log.at.toLocal().toString().substring(11, 19)}  ${log.method}  ${log.status}  ${log.ms}ms  ${log.bytes}B',
                          style: theme.textTheme.labelMedium?.copyWith(color: colour),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(log.url, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                        if (log.error.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(log.error, style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
                        ],
                      ],
                    );
                  },
                ),
        );
      },
    );
  }
}
