/// 播放页：选集 / 竖滑切换 / 倍速 / 失败自动换线路 / 进度记忆。
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/play_queue.dart';
import '../store/app_settings.dart';
import '../store/error_log.dart';
import '../store/history_store.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.episodes,
    required this.title,
    required this.target,
    this.initialIndex = 0,
    this.fallbacks = const <PlayItem>[],
    this.fromStart = false,
    this.episodeList = false,
  });

  /// 播放队列：剧集就是「集」，电影多线路就是「线路」。
  final List<PlayItem> episodes;
  final String title;
  final int initialIndex;

  /// 当前条目换线路时的备用来源（组件的 playSources）。
  final List<PlayItem> fallbacks;

  /// 写进观看历史的定位信息。
  final WatchTarget target;

  /// 为真时忽略已存的进度、从头播（「从头播放」按钮）。
  final bool fromStart;

  /// 队列语义是「剧集」而不是「同一部片的多个线路」—— 只有剧集才自动连播。
  final bool episodeList;

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

  /// 本集是否已经走到「播完」逻辑（防止 _onTick 反复触发）。
  bool _completionHandled = false;

  // ---- 全屏 / 方向 ----
  bool _fullscreen = false;
  bool _landscape = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

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
    _completionHandled = false;
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
    final failures = <String>[];
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
        formatHint: _formatHintOf(candidate.url),
      );
      _controller = controller;
      try {
        await controller.initialize();
        await controller.setPlaybackSpeed(_speed);
        await _restoreProgress(controller);
        await controller.play();
        controller.addListener(_onTick);
        if (!mounted) return;
        setState(() => _initializing = false);
        return;
      } catch (e) {
        lastError = e.toString();
        failures.add('线路 ${i + 1}/${candidates.length}：${candidate.url}\n      → $e');
        await controller.dispose();
        if (identical(_controller, controller)) _controller = null;
        debugPrint('[player] 线路失败（$i/${candidates.length}）：$lastError');
      }
    }

    // ★ 播放失败也记进错误日志。
    //   以前只在界面上显示，用户说「播放不了」时我们拿不到任何原因 ——
    //   带上平台与逐条线路的报错，下一份日志就能直接定位。
    ErrorLog.instance.add(
      '播放',
      '平台=${Platform.operatingSystem} 页面=${widget.title} 条目=${_current.title}\n'
          '${failures.join('\n')}',
      null,
    );

    if (!mounted) return;
    setState(() {
      _error = candidates.length > 1 ? '全部 ${candidates.length} 条线路都播放失败\n$lastError' : lastError;
      _initializing = false;
    });
  }

  /// 给播放器一个**格式提示**。
  ///
  /// Android 走 ExoPlayer、iOS 走 AVPlayer —— 后者能靠内容嗅探，
  /// 前者遇到「地址没有扩展名 / Content-Type 不标准」更容易直接报 Source error，
  /// 这正是「iOS 能播、Android 播不了」最常见的成因之一。
  /// 这里**只在扩展名明确时**给提示，不乱猜。
  VideoFormat? _formatHintOf(String url) {
    final path = Uri.tryParse(url.trim())?.path.toLowerCase() ?? '';
    if (path.endsWith('.m3u8')) return VideoFormat.hls;
    if (path.endsWith('.mpd')) return VideoFormat.dash;
    if (path.endsWith('.mp4') || path.endsWith('.mkv') || path.endsWith('.flv')) return VideoFormat.other;
    return null;
  }

  void _onTick() {
    if (!mounted) return;
    final controller = _controller;
    if (controller != null) {
      final value = controller.value;
      // 播到末尾（位置贴到时长且已停）→ 走「本集播完」逻辑。
      if (value.isInitialized &&
          value.duration > Duration.zero &&
          !value.isPlaying &&
          value.position >= value.duration - const Duration(milliseconds: 500)) {
        unawaited(_handleCompletion());
      }
    }
    setState(() {});
    _maybeSaveProgress();
  }

  /// 本集播完：记「已看完」，再按设置决定是否自动接下一集。
  Future<void> _handleCompletion() async {
    if (_completionHandled) return;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final totalMs = controller.value.duration.inMilliseconds;
    if (totalMs <= 0) return;
    _completionHandled = true;

    await _saveProgress(controller, positionMs: totalMs);

    final hasNext = shouldAutoAdvance(
      currentIndex: _index,
      total: widget.episodes.length,
      enabled: AppSettings.instance.autoPlayNext,
      episodeList: widget.episodeList,
    );
    if (!hasNext) {
      if (widget.episodeList && widget.episodes.length > 1 && _index + 1 >= widget.episodes.length) {
        _flashHint('已经是最后一集');
      }
      return;
    }

    final next = _index + 1;
    _flashHint('自动播放下一集：${widget.episodes[next].title}');
    setState(() => _index = next);
    await _load(candidateIndex: 0);
  }

  String get _recordKey => watchEpisodeKey(widget.target, _current.title);

  /// 续播：恢复上次看到的位置（「从头播放」时跳过，并把记录清零）。
  Future<void> _restoreProgress(VideoPlayerController controller) async {
    if (widget.fromStart) {
      await _saveProgress(controller, positionMs: 0);
      return;
    }
    final record = HistoryStore.instance.find(_recordKey);
    if (record == null || !record.resumable) return;
    if (record.positionMs >= controller.value.duration.inMilliseconds) return;
    await controller.seekTo(Duration(milliseconds: record.positionMs));
    _flashHint('已从 ${_fmt(Duration(milliseconds: record.positionMs))} 继续播放');
  }

  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);

  /// 每 5 秒落一次盘，避免写太勤。
  void _maybeSaveProgress() {
    final now = DateTime.now();
    if (now.difference(_lastSaved) < const Duration(seconds: 5)) return;
    _lastSaved = now;
    unawaited(_saveProgress(_controller));
  }

  Future<void> _saveProgress(VideoPlayerController? controller, {int? positionMs}) async {
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final article = widget.episodes.length > 1 ? _current.title : '';
    await HistoryStore.instance.save(
      WatchRecord(
        key: watchEpisodeKey(widget.target, _current.title),
        target: widget.target,
        episodeTitle: article,
        positionMs: positionMs ?? value.position.inMilliseconds,
        durationMs: durationMs,
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _restoreSystemChrome();
    // 退出时立刻记一次最终位置（读取是同步的，之后再销毁控制器）。
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final value = controller.value;
      if (value.duration.inMilliseconds > 0) {
        unawaited(
          HistoryStore.instance.save(
            WatchRecord(
              key: _recordKey,
              target: widget.target,
              episodeTitle: widget.episodes.length > 1 ? _current.title : '',
              positionMs: value.position.inMilliseconds,
              durationMs: value.duration.inMilliseconds,
            ),
          ),
        );
      }
    }
    controller?.removeListener(_onTick);
    controller?.dispose();
    super.dispose();
  }

  Future<void> _switchEpisode(int delta) async {
    final next = _index + delta;
    if (next < 0 || next >= widget.episodes.length) {
      _flashHint(delta > 0 ? '已经是最后一集' : '已经是第一集');
      return;
    }
    // 切集前先把当前这集的位置记下来。
    await _saveProgress(_controller);
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

  /* --------------------------------------------------------- 方向 / 全屏 */

  Future<void> _applyOrientation() async {
    await SystemChrome.setPreferredOrientations(
      _landscape
          ? const <DeviceOrientation>[DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : const <DeviceOrientation>[DeviceOrientation.portraitUp],
    );
  }

  /// 只切换横竖屏，不动全屏状态。
  Future<void> _toggleOrientation() async {
    setState(() => _landscape = !_landscape);
    await _applyOrientation();
    _scheduleHide();
  }

  /// 进入/退出全屏：全屏时隐藏系统栏与 AppBar，默认转横屏。
  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() {
      _fullscreen = next;
      _controlsVisible = true;
      if (next) _landscape = true; // 全屏默认横屏
    });
    await _applyOrientation();
    await SystemChrome.setEnabledSystemUIMode(
      next ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (next) _scheduleHide();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  /// 全屏时控制层 5 秒无操作自动隐藏。
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_fullscreen) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  /// 退出播放页时恢复系统 UI（方向锁放开、状态栏回来）。
  void _restoreSystemChrome() {
    unawaited(SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
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
    await _saveProgress(_controller);
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

  /// 自动连播开关（只在剧集模式下出现）。
  Widget _autoPlayNextButton() {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final on = AppSettings.instance.autoPlayNext;
        return IconButton(
          tooltip: on ? '自动连播：开' : '自动连播：关',
          onPressed: () => AppSettings.instance.setAutoPlayNext(!on),
          color: on ? Theme.of(context).colorScheme.primary : null,
          icon: Icon(on ? Icons.playlist_play : Icons.playlist_remove, size: 22),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final total = widget.episodes.length;

    // ★ 手势层只包住「视频区」，控制条放在它外面 —— 否则整屏的
    //   onVerticalDragEnd 会和进度条的横向拖拽抢手势，进度条根本拖不动。
    final videoArea = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 全屏时点一下视频呼出/收起控制层。
      onTap: _fullscreen ? _toggleControls : null,
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
                    : AspectRatio(
                        aspectRatio: ready ? controller.value.aspectRatio : 16 / 9,
                        child: ready ? VideoPlayer(controller) : const SizedBox.shrink(),
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
    );

    // ---- 全屏：没有 AppBar / 底部栏，控制层浮在视频上 ----
    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: <Widget>[
            Positioned.fill(child: videoArea),
            if (_controlsVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _FullscreenActions(
                          episodeLabel: widget.episodes.length > 1 ? '选集 ${_index + 1}/${widget.episodes.length}' : null,
                          onEpisodes: widget.episodes.length > 1 ? _openEpisodeSheet : null,
                          sourceLabel: _candidates.length > 1 ? '线路 ${_candidateIndex + 1}/${_candidates.length}' : null,
                          onSources: _candidates.length > 1 ? _openSourceSheet : null,
                          speedLabel: '${_speed}x',
                          onSpeed: _openSpeedSheet,
                          onOrientation: _toggleOrientation,
                          landscape: _landscape,
                          onExitFullscreen: _toggleFullscreen,
                          autoPlayToggle: (widget.episodeList && widget.episodes.length > 1) ? _autoPlayNextButton() : null,
                        ),
                        if (ready) _Controls(controller: controller, fmt: _fmt, transparent: true),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          total > 1 ? '${widget.title} · ${_current.title}' : widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: _landscape ? '切换为竖屏' : '切换为横屏',
            onPressed: _toggleOrientation,
            icon: Icon(_landscape ? Icons.stay_current_portrait : Icons.stay_current_landscape),
          ),
          IconButton(tooltip: '全屏', onPressed: _toggleFullscreen, icon: const Icon(Icons.fullscreen)),
          IconButton(tooltip: '用系统播放器打开', onPressed: _openExternally, icon: const Icon(Icons.open_in_new)),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: videoArea),
          if (ready) _Controls(controller: controller, fmt: _fmt),
        ],
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
                    if (widget.episodeList && widget.episodes.length > 1) _autoPlayNextButton(),
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
  const _Controls({required this.controller, required this.fmt, this.transparent = false});

  final VideoPlayerController controller;
  final String Function(Duration) fmt;

  /// 全屏时用半透明底（浮在视频上）。
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    return Container(
      color: transparent ? Colors.transparent : Colors.black,
      padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
      child: Row(
        children: <Widget>[
          IconButton(
            color: Colors.white,
            iconSize: 34,
            tooltip: value.isPlaying ? '暂停' : '播放',
            onPressed: () => value.isPlaying ? controller.pause() : controller.play(),
            icon: Icon(value.isPlaying ? Icons.pause_circle : Icons.play_circle),
          ),
          Text(fmt(value.position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Expanded(child: _Scrubber(controller: controller)),
          Text(fmt(value.duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
          SizedBox(
            width: 18,
            child: value.isBuffering
                ? const Center(
                    child: SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// 可拖拽进度条。
///
/// 用 `Slider` 而不是 `VideoProgressIndicator`：后者轨道只有几像素高、
/// 触摸区太窄，配合整屏的手势识别器经常抢不到手势，表现就是「拖不动」。
/// `Slider` 自带 ~48dp 的命中高度，且这里已经和上/下滑切集的手势层分离。
class _Scrubber extends StatefulWidget {
  const _Scrubber({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final total = value.duration.inMilliseconds;
    if (total <= 0) return const SizedBox(height: 40);

    final current = (_dragValue ?? value.position.inMilliseconds.toDouble()).clamp(0.0, total.toDouble());
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: Colors.white,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: const Color(0x33FFFFFF),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      child: Slider(
        min: 0,
        max: total.toDouble(),
        value: current,
        onChanged: (v) => setState(() => _dragValue = v),
        onChangeEnd: (v) async {
          await widget.controller.seekTo(Duration(milliseconds: v.round()));
          if (mounted) setState(() => _dragValue = null);
        },
      ),
    );
  }
}

/// 全屏时浮在视频上的辅助操作行（选集 / 线路 / 倍速 / 方向 / 退出全屏）。
class _FullscreenActions extends StatelessWidget {
  const _FullscreenActions({
    required this.episodeLabel,
    required this.onEpisodes,
    required this.sourceLabel,
    required this.onSources,
    required this.speedLabel,
    required this.onSpeed,
    required this.onOrientation,
    required this.landscape,
    required this.onExitFullscreen,
    this.autoPlayToggle,
  });

  final String? episodeLabel;
  final VoidCallback? onEpisodes;
  final String? sourceLabel;
  final VoidCallback? onSources;
  final String speedLabel;
  final VoidCallback onSpeed;
  final VoidCallback onOrientation;
  final bool landscape;
  final VoidCallback onExitFullscreen;

  /// 「自动连播」开关（剧集模式才有）。
  final Widget? autoPlayToggle;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(foregroundColor: Colors.white, visualDensity: VisualDensity.compact);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: <Widget>[
          if (episodeLabel != null)
            TextButton(onPressed: onEpisodes, style: style, child: Text(episodeLabel!)),
          if (sourceLabel != null)
            TextButton(onPressed: onSources, style: style, child: Text(sourceLabel!)),
          TextButton(onPressed: onSpeed, style: style, child: Text(speedLabel)),
          const Spacer(),
          if (autoPlayToggle != null) autoPlayToggle!,
          IconButton(
            tooltip: landscape ? '切换为竖屏' : '切换为横屏',
            color: Colors.white,
            onPressed: onOrientation,
            icon: Icon(landscape ? Icons.stay_current_portrait : Icons.stay_current_landscape),
          ),
          IconButton(
            tooltip: '退出全屏',
            color: Colors.white,
            onPressed: onExitFullscreen,
            icon: const Icon(Icons.fullscreen_exit),
          ),
        ],
      ),
    );
  }
}
