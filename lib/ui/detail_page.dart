/// 详情页：链接类条目先走 loadDetail 二次解析，再落到剧集/线路列表。
library;

import 'package:flutter/material.dart';

import '../models/capy_models.dart';
import '../models/play_queue.dart';
import '../runtime/widget_runtime.dart';
import '../store/history_store.dart';
import 'common.dart';
import 'player_page.dart';
import 'poster_image.dart';

/// 把毫秒格式化成 `12:34` / `1:02:03`。
String _fmtMs(int milliseconds) {
  final d = Duration(milliseconds: milliseconds);
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = d.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.runtime, required this.item, this.pluginTitle = ''});

  final WidgetRuntime runtime;
  final MediaItem item;
  final String pluginTitle;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  CapyDetail? _detail;
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.item.needsDetail) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final detail = await widget.runtime.loadDetail(widget.item);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, String> _headersOf(Map<String, String> own) {
    if (own.isNotEmpty) return own;
    final detailHeaders = _detail?.customHeaders ?? const <String, String>{};
    if (detailHeaders.isNotEmpty) return detailHeaders;
    return widget.item.customHeaders;
  }

  /// 播放队列：有分集就是「集」，只有线路就是「线路」。
  List<PlayItem> get _queue {
    final detail = _detail;
    final episodes = detail?.allEpisodes ?? const <Episode>[];
    if (episodes.isNotEmpty) {
      return episodes
          .map((e) => PlayItem(
                title: e.title,
                url: e.videoUrl,
                headers: _headersOf(e.customHeaders),
                playerType: 'system',
              ))
          .where((item) => !item.isEmpty)
          .toList();
    }
    final sources = detail?.playSources ?? const <PlaySource>[];
    if (sources.isNotEmpty) {
      return sources
          .map((s) => PlayItem(
                title: s.title,
                url: s.videoUrl,
                headers: _headersOf(s.customHeaders),
                playerType: s.playerType,
              ))
          .where((item) => !item.isEmpty)
          .toList();
    }
    final directUrl = (detail?.videoUrl.isNotEmpty ?? false) ? detail!.videoUrl : widget.item.videoUrl;
    if (directUrl.isNotEmpty) {
      return <PlayItem>[
        PlayItem(
          title: '默认线路',
          url: directUrl,
          headers: _headersOf(widget.item.customHeaders),
          // 以「详情」的声明为准：MissAV 列表项给 none，详情才给 system。
          playerType: (detail?.playerType.isNotEmpty ?? false) ? detail!.playerType : widget.item.playerType,
        ),
      ];
    }
    return const <PlayItem>[];
  }

  /// 换线路用的备用来源：分集播放时，playSources 是同集的其它线路。
  List<PlayItem> get _fallbacks {
    final detail = _detail;
    if (detail == null || detail.allEpisodes.isEmpty) return const <PlayItem>[];
    return detail.playSources
        .map((s) => PlayItem(
              title: '备用·${s.title}',
              url: s.videoUrl,
              headers: _headersOf(s.customHeaders),
              playerType: s.playerType,
            ))
        .where((item) => !item.isEmpty)
        .toList();
  }

  /// 写观看历史用的定位信息（插件 id + 媒体 id + 标题/封面/详情链接）。
  WatchTarget get _target {
    final item = widget.item;
    final mediaId = item.id.isNotEmpty
        ? item.id
        : (item.link.isNotEmpty ? item.link : item.title);
    final poster = (_detail?.posterUrl.isNotEmpty ?? false) ? _detail!.posterUrl : item.posterUrl;
    return WatchTarget(
      pluginId: widget.runtime.record.id,
      mediaId: mediaId,
      title: _title,
      posterUrl: poster,
      link: item.link,
    );
  }

  /// 队列是「剧集」还是「同一部片的多个线路」—— 只有前者才做自动连播。
  bool get _isEpisodeMode => _detail?.allEpisodes.isNotEmpty ?? false;

  void _play(int index, {bool fromStart = false}) {
    final queue = _queue;
    if (queue.isEmpty) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerPage(
              episodes: queue,
              initialIndex: index.clamp(0, queue.length - 1),
              title: _title,
              target: _target,
              fallbacks: _fallbacks,
              fromStart: fromStart,
              episodeList: _isEpisodeMode,
            ),
          ),
        )
        .then((_) {
      // 从播放页回来刷新「继续观看」按钮。
      if (mounted) setState(() {});
    });
  }

  String get _title {
    final detail = _detail;
    if (detail != null && detail.title.isNotEmpty) return detail.title;
    return widget.item.title;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = _detail;
    final item = widget.item;
    final title = _title;
    final poster = (detail?.posterUrl.isNotEmpty ?? false) ? detail!.posterUrl : item.posterUrl;
    final backdrop = (detail?.backdropUrl.isNotEmpty ?? false) ? detail!.backdropUrl : item.backdropUrl;
    final description = (detail?.description.isNotEmpty ?? false) ? detail!.description : item.description;
    final queue = _queue;
    final episodes = detail?.allEpisodes ?? const <Episode>[];
    final sources = detail?.playSources ?? const <PlaySource>[];
    // 观看历史：这部剧/电影上次看到哪了。
    final resume = HistoryStore.instance.latestForMedia(_target.mediaKey);
    final resumeIndex = (resume == null || resume.episodeTitle.isEmpty)
        ? 0
        : queue.indexWhere((item) => item.title == resume.episodeTitle);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          if (backdrop.isNotEmpty)
            PosterImage(
              url: backdrop,
              height: 180,
              referer: widget.runtime.imageReferer,
              fallback: const SizedBox(height: 180),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (poster.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: PosterImage(
                      url: poster,
                      width: 110,
                      height: 165,
                      referer: widget.runtime.imageReferer,
                      fallback: const SizedBox(width: 110, height: 165),
                    ),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: theme.textTheme.titleLarge),
                      if (widget.pluginTitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text('来源：${widget.pluginTitle}', style: theme.textTheme.bodySmall),
                      ],
                      if (item.remark.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(item.remark, style: theme.textTheme.bodySmall),
                      ],
                      if (detail?.tags.isNotEmpty == true) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            for (final tag in detail!.tags.take(8))
                              Chip(label: Text(tag), visualDensity: VisualDensity.compact),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (queue.isNotEmpty) ...<Widget>[
                        if (resume != null && resume.resumable)
                          FilledButton.icon(
                            onPressed: () => _play(resumeIndex < 0 ? 0 : resumeIndex),
                            icon: const Icon(Icons.play_arrow),
                            label: Text('继续观看 · ${_fmtMs(resume.positionMs)}'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => _play(0),
                            icon: const Icon(Icons.play_arrow),
                            label: Text(episodes.length > 1 ? '从第 1 集开始（共 ${episodes.length} 集）' : '立即播放'),
                          ),
                        if (resume != null && resume.resumable)
                          TextButton.icon(
                            onPressed: () => _play(resumeIndex < 0 ? 0 : resumeIndex, fromStart: true),
                            icon: const Icon(Icons.replay, size: 18),
                            label: const Text('从头播放'),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ErrorBanner(message: _error, onRetry: _load)),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(description, style: theme.textTheme.bodyMedium),
            ),
          if (episodes.isEmpty && sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('播放线路', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (var i = 0; i < sources.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(sources[i].title),
                      subtitle: sources[i].description.isEmpty ? null : Text(sources[i].description),
                      onTap: () => _play(i),
                    ),
                ],
              ),
            ),
          if (episodes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: Text('选集（${episodes.length}）', style: theme.textTheme.titleMedium)),
                      if (queue.isNotEmpty)
                        TextButton(
                          onPressed: () => _play(0),
                          child: const Text('全屏选集'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (var i = 0; i < episodes.length; i++)
                        OutlinedButton(
                          onPressed: () => _play(i),
                          child: Text(episodes[i].title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (!_loading && _error.isEmpty && detail != null && queue.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('该条目没有解析到可播放地址')),
            ),
        ],
      ),
    );
  }
}
