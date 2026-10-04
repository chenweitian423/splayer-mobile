/// 观看历史：续播入口 + 记录清理。
library;

import 'package:flutter/material.dart';

import '../models/capy_models.dart';
import '../runtime/plugin_engine.dart';
import '../store/history_store.dart';
import '../store/plugin_store.dart';
import 'detail_page.dart';
import 'poster_image.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, this.embedded = true});

  /// 作为底部标签页时内嵌（无 Scaffold）；从设置里打开时自带 AppBar。
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HistoryStore.instance,
      builder: (context, _) {
        final body = _HistoryBody(embedded: embedded);
        if (embedded) return body;
        return Scaffold(appBar: AppBar(title: const Text('观看历史')), body: body);
      },
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.embedded});

  final bool embedded;

  static PluginRecord? _findPlugin(String id) {
    for (final candidate in PluginStore.instance.records) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  Future<void> _open(BuildContext context, WatchRecord record) async {
    final plugin = _findPlugin(record.target.pluginId);
    final messenger = ScaffoldMessenger.of(context);
    if (plugin == null) {
      messenger.showSnackBar(const SnackBar(content: Text('这条记录对应的组件已被删除或停用')));
      return;
    }
    if (!plugin.enabled) {
      messenger.showSnackBar(SnackBar(content: Text('组件「${plugin.title}」已被停用，请先在插件页启用')));
      return;
    }
    try {
      final runtime = await PluginEngine.instance.runtimeFor(plugin);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailPage(
            runtime: runtime,
            item: MediaItem(
              id: record.target.mediaId,
              title: record.target.title,
              posterUrl: record.target.posterUrl,
              link: record.target.link,
            ),
            pluginTitle: plugin.title,
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('打开失败：$e')));
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看历史？'),
        content: Text('将删除全部 ${HistoryStore.instance.count} 条记录，播放进度也会一并清除，无法撤销。'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
        ],
      ),
    );
    if (confirmed != true) return;
    await HistoryStore.instance.clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空观看历史')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = HistoryStore.instance.records;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text('共 ${records.length} 条', style: theme.textTheme.bodySmall),
              ),
              if (records.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClear(context),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('清空'),
                ),
            ],
          ),
        ),
        if (records.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.history, size: 52, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text('还没有观看记录', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 6),
                    Text(
                      '播放过的影片会自动记在这里，下次点开可续播',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: records.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) => _HistoryTile(
                record: records[index],
                onTap: () => _open(context, records[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record, required this.onTap});

  final WatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = record.progress;
    return Dismissible(
      key: ValueKey<String>(record.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.errorContainer,
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) {
        HistoryStore.instance.remove(record.key);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除「${record.target.title}」的记录')),
        );
      },
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PosterImage(
                  url: record.target.posterUrl,
                  width: 64,
                  height: 92,
                  fallback: Container(
                    width: 64,
                    height: 92,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.movie_outlined, color: theme.colorScheme.outline),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      record.target.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (record.episodeTitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(record.episodeTitle, style: theme.textTheme.bodySmall),
                    ],
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: record.finished ? 1 : progress,
                        minHeight: 3,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      record.finished
                          ? '已看完 · ${_relative(record.updatedAt)}'
                          : '看到 ${_fmt(Duration(milliseconds: record.positionMs))}'
                              '${record.durationMs > 0 ? ' / ${_fmt(Duration(milliseconds: record.durationMs))}' : ''}'
                              ' · ${_relative(record.updatedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除这条记录',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  HistoryStore.instance.remove(record.key);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除「${record.target.title}」的记录')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _relative(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
