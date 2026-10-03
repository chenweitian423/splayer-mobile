/// 播放页：选集 / 竖滑切换 / 倍速 / 失败自动换线路。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/play_queue.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.episodes,
    required this.title,
    this.initialIndex = 0,
    this.fallbacks = const <PlayItem>[],
  });

  /// 播放队列：剧集就是「集」，电影多线路就是「线路」。
  final List<PlayItem> episodes;
  final String title;
  final int initialIndex;

  /// 当前条目换线路时的备用来源（组件的 playSources）。
  final List<PlayItem> fallbacks;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  late int _index = widget.initialIndex.clamp(0, widget.episodes.isEmpty ? 0 : widget.episodes.length - 1);
  int _candidateIndex = 0;
  double _speed = 1.0;
  bool _initializing = true;
  String _error = '';
  String _triedUrl = '';
  bool _showEpisodeHint = false;
  String _hintText = '';

  List<PlayCandidate> get _candidates => <PlayCandidate>[
        ...widget.episodes[_index].candidates,
        ...widget.fallbacks.expand((item) => item.candidates),
      ];

  PlayItem get _current => widget.episodes[_index];

  @override
  void initState() {
    super.initState();
    _load(candidateIndex: 0);
  }

  /// 依次尝试候选地址，全部失败才报错（mpv 变体 → hls 兼容 → 备用线路）。
  Future<void> _load({required int candidateIndex}) async {
    final candidates = _candidates;
    if (candidates.isEmpty) {
      setState(() {
        _error = '该条目没有可播放地址';
        _initializing = false;
      });
      return;
    }

    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = '';
      });
    }

    String lastError = '';
    for (var i = candidateIndex; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (!mounted) return;
      setState(() {
        _candidateIndex = i;
        _triedUrl = candidate.url;
      });

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(candidate.url),
        httpHeaders: candidate.headers,
      );
      _controller = controller;
      try {
        await controller.initialize();
        await controller.setPlaybackSpeed(_speed);
        await controller.play();
        controller.addListener(_onTick);
        if (!mounted) return;
        setState(() => _initializing = false);
        return;
      } catch (e) {
        lastError = e.toString();
        await controller.dispose();
        if (identical(_controller, controller)) _controller = null;
        debugPrint('[player] 线路失败（$i/${candidates.length}）：$lastError');
      }
    }

    if (!mounted) return;
    setState(() {
      _error = candidates.length > 1 ? '全部 ${candidates.length} 条线路都播放失败\n$lastError' : lastError;
      _initializing = false;
    });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _switchEpisode(int delta) async {
    final next = _index + delta;
    if (next < 0 || next >= widget.episodes.length) {
      _flashHint(delta > 0 ? '已经是最后一集' : '已经是第一集');
      return;
    }
    setState(() => _index = next);
    _flashHint('${delta > 0 ? '下一集' : '上一集'}：${widget.episodes[next].title}');
    await _load(candidateIndex: 0);
  }

  void _flashHint(String text) {
    setState(() {
      _hintText = text;
      _showEpisodeHint = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _showEpisodeHint = false);
    });
  }

  String _fmt(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _openEpisodeSheet() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EpisodeSheet(episodes: widget.episodes, current: _index),
    );
    if (picked == null || picked == _index) return;
    setState(() => _index = picked);
    await _load(candidateIndex: 0);
  }

  Future<void> _openSourceSheet() async {
    final candidates = _candidates;
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const ListTile(title: Text('切换线路'), dense: true),
            for (var i = 0; i < candidates.length; i++)
              ListTile(
                leading: Icon(i == _candidateIndex ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                title: Text(candidates[i].label),
                subtitle: Text(
                  candidates[i].url,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10),
                ),
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _candidateIndex) return;
    await _load(candidateIndex: picked);
  }

  Future<void> _openSpeedSheet() async {
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final picked = await showModalBottomSheet<double>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const ListTile(title: Text('播放速度'), dense: true),
            for (final speed in speeds)
              ListTile(
                leading: Icon(speed == _speed ? Icons.check_circle : Icons.speed),
                title: Text('${speed}x'),
                onTap: () => Navigator.pop(context, speed),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _speed = picked;
    await _controller?.setPlaybackSpeed(picked);
    if (mounted) setState(() {});
  }

  Future<void> _copyError() async {
    final text = 'SPlayer Mobile 播放失败\n标题：${widget.title}\n'
        '条目：${_current.title}\n错误：$_error\n地址：$_triedUrl';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制，直接发我即可')));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final total = widget.episodes.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          total > 1 ? '${widget.title} · ${_current.title}' : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(tooltip: '用系统播放器打开', onPressed: _openExternally, icon: const Icon(Icons.open_in_new)),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 上下滑切集（上滑下一集 / 下滑上一集）
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -250) {
            _switchEpisode(1);
          } else if (velocity > 250) {
            _switchEpisode(-1);
          }
        },
        child: Stack(
          children: <Widget>[
            Center(
              child: _error.isNotEmpty && !ready
                  ? _ErrorView(
                      error: _error,
                      url: _triedUrl,
                      onRetry: () => _load(candidateIndex: 0),
                      onSwitchSource: _openSourceSheet,
                      onCopy: _copyError,
                    )
                  : _initializing
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            AspectRatio(
                              aspectRatio: ready ? controller.value.aspectRatio : 16 / 9,
                              child: ready ? VideoPlayer(controller) : const SizedBox.shrink(),
                            ),
                            if (ready) _Controls(controller: controller, fmt: _fmt),
                          ],
                        ),
            ),
            if (_showEpisodeHint)
              Positioned(
                left: 0,
                right: 0,
                top: 24,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_hintText, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: (_error.isNotEmpty && !ready)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: <Widget>[
                    if (widget.episodes.length > 1)
                      TextButton.icon(
                        onPressed: _openEpisodeSheet,
                        icon: const Icon(Icons.list_alt, size: 18),
                        label: Text('选集 ${_index + 1}/${widget.episodes.length}'),
                      ),
                    const Spacer(),
                    if (_candidates.length > 1)
                      TextButton.icon(
                        onPressed: _openSourceSheet,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: Text('线路 ${_candidateIndex + 1}/${_candidates.length}'),
                      ),
                    TextButton.icon(
                      onPressed: _openSpeedSheet,
                      icon: const Icon(Icons.speed, size: 18),
                      label: Text('${_speed}x'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(_current.url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.url,
    required this.onRetry,
    required this.onSwitchSource,
    required this.onCopy,
  });

  final String error;
  final String url;
  final VoidCallback onRetry;
  final VoidCallback onSwitchSource;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.play_disabled_outlined, color: Colors.white54, size: 44),
          const SizedBox(height: 12),
          const Text('播放失败', style: TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 12),
          Text(url, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white30, fontSize: 10)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: <Widget>[
              FilledButton(onPressed: onRetry, child: const Text('重试')),
              OutlinedButton(onPressed: onSwitchSource, child: const Text('换线路')),
              TextButton(onPressed: onCopy, child: const Text('复制错误')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.episodes, required this.current});

  final List<PlayItem> episodes;
  final int current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('选集（${episodes.length}）', style: Theme.of(context).textTheme.titleSmall),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  childAspectRatio: 2.4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, index) => OutlinedButton(
                  onPressed: () => Navigator.pop(context, index),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: index == current ? Theme.of(context).colorScheme.primaryContainer : null,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: Text(
                    episodes[index].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, required this.fmt});

  final VideoPlayerController controller;
  final String Function(Duration) fmt;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: <Widget>[
          VideoProgressIndicator(controller, allowScrubbing: true, padding: const EdgeInsets.symmetric(vertical: 8)),
          Row(
            children: <Widget>[
              IconButton(
                color: Colors.white,
                iconSize: 34,
                onPressed: () => controller.value.isPlaying ? controller.pause() : controller.play(),
                icon: Icon(value.isPlaying ? Icons.pause_circle : Icons.play_circle),
              ),
              const SizedBox(width: 8),
              Text(
                '${fmt(value.position)} / ${fmt(value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              Text(
                controller.value.playbackSpeed == 1.0 ? '' : '${controller.value.playbackSpeed}x',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
