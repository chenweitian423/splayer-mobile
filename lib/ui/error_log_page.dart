/// 错误日志页：闪退/异常记录，一键复制发给开发者。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store/error_log.dart';

class ErrorLogPage extends StatelessWidget {
  const ErrorLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ErrorLog.instance,
      builder: (context, _) {
        final entries = ErrorLog.instance.entries;
        return Scaffold(
          appBar: AppBar(
            title: Text('错误日志（${entries.length}）'),
            actions: <Widget>[
              IconButton(
                tooltip: '复制全部',
                onPressed: entries.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: ErrorLog.instance.asText()));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制，直接发我即可')),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_all_outlined),
              ),
              IconButton(
                tooltip: '清空',
                onPressed: entries.isEmpty
                    ? null
                    : () => ErrorLog.instance.clear(),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          body: entries.isEmpty
              ? const Center(child: Text('暂无错误记录'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 20),
                  itemBuilder: (context, index) => SelectableText(
                    entries[index],
                    style: const TextStyle(fontSize: 11, height: 1.5, fontFamily: 'monospace'),
                  ),
                ),
        );
      },
    );
  }
}
