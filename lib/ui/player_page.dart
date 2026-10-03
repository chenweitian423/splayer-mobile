/// 播放页：video_player（Android: ExoPlayer / iOS: AVPlayer）。
///
/// 之所以用官方 video_player 而不是 mpv：CI 里能稳定出包，且 m3u8 + 自定义
/// 请求头在两端都支持（组件返回的 customHeaders 直接透传）。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.url, required this.title, this.headers = const <String, String>{}});

  final String url;
  final String title;
  final Map<String, String> headers;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  String _error = '';
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.headers,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.play();
      controller.addListener(_onTick);
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _initializing = false;
      });
    }
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

  String _fmt(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: '用系统播放器打开',
            onPressed: () async {
              final uri = Uri.parse(widget.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: Center(
        child: _error.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.play_disabled_outlined, color: Colors.white54, size: 48),
                    const SizedBox(height: 12),
                    Text('播放失败：$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    Text(widget.url, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  ],
                ),
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
                '${value.size.height.toStringAsFixed(0)}p',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
