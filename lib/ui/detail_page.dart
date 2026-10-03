/// 详情页：链接类条目先走 loadDetail 二次解析，再落到剧集/线路列表。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/capy_models.dart';
import '../runtime/widget_runtime.dart';
import 'common.dart';
import 'player_page.dart';

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

  void _playUrl(String url, Map<String, String> headers, String title) {
    if (url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(url: url, headers: headers, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = _detail;
    final item = widget.item;
    final title = detail?.title.isNotEmpty == true ? detail!.title : item.title;
    final poster = detail?.posterUrl.isNotEmpty == true ? detail!.posterUrl : item.posterUrl;
    final backdrop = detail?.backdropUrl.isNotEmpty == true ? detail!.backdropUrl : item.backdropUrl;
    final description = detail?.description.isNotEmpty == true ? detail!.description : item.description;
    final episodes = detail?.allEpisodes ?? const <Episode>[];
    final sources = detail?.playSources ?? const <PlaySource>[];
    final directUrl = detail?.videoUrl.isNotEmpty == true ? detail!.videoUrl : item.videoUrl;
    final headers = detail?.customHeaders.isNotEmpty == true ? detail!.customHeaders : item.customHeaders;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          if (backdrop.isNotEmpty)
            CachedNetworkImage(
              imageUrl: backdrop,
              height: 180,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (poster.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: poster,
                      width: 110,
                      height: 165,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox(width: 110, height: 165),
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
                      if (directUrl.isNotEmpty)
                        FilledButton.icon(
                          onPressed: () => _playUrl(directUrl, headers, title),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('立即播放'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ErrorBanner(message: _error, onRetry: _load)),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(description, style: theme.textTheme.bodyMedium),
            ),
          if (sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('播放线路', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final source in sources)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_circle_outline),
                      title: Text(source.title),
                      subtitle: source.description.isEmpty ? null : Text(source.description),
                      onTap: () => _playUrl(source.videoUrl, source.customHeaders, '$title · ${source.title}'),
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
                  Text('选集（${episodes.length}）', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final episode in episodes)
                        OutlinedButton(
                          onPressed: () => _playUrl(episode.videoUrl, episode.customHeaders, '$title · ${episode.title}'),
                          child: Text(episode.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          if (!_loading && _error.isEmpty && detail != null && episodes.isEmpty && sources.isEmpty && directUrl.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('该条目没有解析到可播放地址')),
            ),
        ],
      ),
    );
  }
}
