/// 在线更新的交互流程：检查 → 说明 → 下载（带进度）→ 调起系统安装器。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../store/update_service.dart';

/// 走一遍「检查更新」。[silent] 为真时不弹「已是最新」的提示（启动时静默检查用）。
Future<void> checkAndUpdate(BuildContext context, {bool silent = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  final theme = Theme.of(context);

  UpdateInfo? info;
  try {
    info = await UpdateService.instance.check();
  } catch (e) {
    if (!silent) {
      messenger.showSnackBar(SnackBar(content: Text('检查更新失败：$e')));
    }
    return;
  }
  if (info == null) {
    if (!silent) {
      final current = await UpdateService.instance.currentVersion();
      messenger.showSnackBar(SnackBar(content: Text('已是最新版本（v$current）')));
    }
    return;
  }
  if (!context.mounted) return;

  final sizeText = info.apk.size > 0 ? '${(info.apk.size / 1048576).toStringAsFixed(1)} MB' : '未知大小';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('发现新版本 v${info!.latestVersion}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('安装包：${info.apk.name}\n大小：$sizeText', style: theme.textTheme.bodySmall),
            if (info.notes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('更新内容', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(info.notes.trim(), style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Text(
              '下载后会调起系统安装器；若提示「应用未安装」，请先卸载旧版本再装（签名不一致时会这样）。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('稍后')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('下载并安装')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final progress = ValueNotifier<double?>(0);
  var downloading = true;
  final dialogFuture = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('正在下载更新'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: value),
              const SizedBox(height: 10),
              Text(
                !downloading
                    ? '下载完成，正在调起安装器…'
                    : value == null
                        ? '下载中…'
                        : '${(value * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  File? apk;
  Object? error;
  try {
    apk = await UpdateService.instance.download(
      info.apk,
      onProgress: (value) => progress.value = value,
    );
  } catch (e) {
    error = e;
  }
  downloading = false;
  progress.value = 1;
  // 给进度条一帧时间显示「下载完成」。
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await dialogFuture;

  if (error != null || apk == null) {
    messenger.showSnackBar(SnackBar(content: Text('下载失败：$error')));
    return;
  }

  try {
    final result = await OpenFilex.open(apk.path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        SnackBar(content: Text('调起安装器失败：${result.message}（文件在 ${apk.path}）')),
      );
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('调起安装器失败：$e')));
  }
}
