/// 播放队列与候选线路。
///
/// 组件交回来的播放地址有两类坑：
///   * 有些地址是给 **mpv 内核**用的（后端按 `player=mpv` 下发），系统播放器
///     （AVPlayer / ExoPlayer）解析不了 —— MissAV 就是典型：插件顶部写死
///     `MISSAV_PLAYER_MODE = "mpv"`，而它自己注释里也写了「显式指定 hls/system 时
///     由服务端下发符合 Apple/FFmpeg 标准的 HLS master」。
///   * 同一集的线路可能不止一条，第一条不通不代表没得播。
///
/// 所以播放前把「一个条目」展开成**有序候选列表**，失败自动换下一条。
library;

class PlayCandidate {
  const PlayCandidate({required this.url, required this.label, this.headers = const {}});

  final String url;
  final String label;
  final Map<String, String> headers;
}

class PlayItem {
  const PlayItem({
    required this.title,
    required this.url,
    this.headers = const {},
    this.playerType = 'system',
    this.subtitle = '',
  });

  final String title;
  final String url;
  final Map<String, String> headers;
  final String playerType;
  final String subtitle;

  bool get isEmpty => url.isEmpty;

  /// 该条目可尝试的地址，按优先级排列。
  List<PlayCandidate> get candidates => playUrlCandidates(url, headers: headers, playerType: playerType);
}

/// `player=mpv` 的后端地址改写为 hls 变体（系统播放器用）。
/// 只动查询参数，其它部分逐字保留。
///
/// 注意：Dart 的 `String.replaceAll` **不支持 `$1` 反向引用**（会把 `$1` 当字面量），
/// 必须用 `replaceAllMapped` 才能拼回前导的 `?` / `&`。
String? rewriteMpvToHls(String url) {
  if (!url.contains('player=mpv')) return null;
  final pattern = RegExp(r'([?&])player=mpv(?![\w])');
  if (!pattern.hasMatch(url)) return null;
  return url.replaceAllMapped(pattern, (match) => '${match.group(1)}player=hls');
}

/// 后端播放代理的 `/media` 端点**实际下发的是 HLS 清单**。
///
/// 实测（curl 打真实地址）：`Content-Type: application/vnd.apple.mpegurl`，
/// 且与同源的 `/playlist.m3u8` 返回**字节完全相同**。
///
/// 问题在于它**路径没有扩展名**：
///   * iOS 的 AVPlayer 会嗅探内容类型 → 能播；
///   * Android 的 ExoPlayer 只会按 URI 扩展名/声明类型判断 → 认成「未知」，
///     拿渐进式解析器去啃 m3u8 文本，直接
///     `ExoPlaybackException: Source error`。
/// 这就解释了「同一部片 iOS 能播、Android 播不了」。
///
/// 这里把末段 `/media` 换成同源的 `/playlist.m3u8`，让 Android 也能正确识别。
/// **只替换末段**，token 与查询串逐字保留（token 是签名的一部分，动一个字节就废）。
String? rewriteBackendPlaybackToHls(String url) {
  final match = RegExp(r'^(.*/playback/[^/?#]+)/media([?#].*)?$').firstMatch(url.trim());
  if (match == null) return null;
  return '${match.group(1)}/playlist.m3u8${match.group(2) ?? ''}';
}

/// 一集播完是否该自动切下一集。
///
/// 三个前提缺一不可：
///   * 开关打开；
///   * 队列是「剧集」而不是「同一部片的多个线路」—— 后者自动跳会变成换线路，
///     不是用户想要的「连播」；
///   * 后面确实还有。
bool shouldAutoAdvance({
  required int currentIndex,
  required int total,
  required bool enabled,
  required bool episodeList,
}) =>
    enabled && episodeList && total > 1 && currentIndex + 1 < total;

/// 生成播放候选：
///   1. 声明了 mpv 内核（URL 带 `player=mpv` 或 playerType=mpv）→ 先试 hls 兼容变体；
///   2. 后端播放代理的无扩展名 `/media` → 先试同源 `/playlist.m3u8`
///      （它下发的本来就是 HLS，但 Android 靠扩展名识别，认不出来）；
///   3. 其它情况原地址优先（保持组件原意）。
List<PlayCandidate> playUrlCandidates(
  String url, {
  Map<String, String> headers = const {},
  String playerType = 'system',
}) {
  if (url.isEmpty) return const <PlayCandidate>[];
  final result = <PlayCandidate>[];
  final seen = <String>{};

  void add(String candidateUrl, String label) {
    if (candidateUrl.isEmpty || !seen.add(candidateUrl)) return;
    result.add(PlayCandidate(url: candidateUrl, label: label, headers: headers));
  }

  final mpvDeclared = playerType.toLowerCase() == 'mpv' || url.contains('player=mpv');
  final hls = rewriteMpvToHls(url);
  final proxyHls = rewriteBackendPlaybackToHls(url);

  if (mpvDeclared && hls != null) {
    add(hls, 'HLS 兼容线路');
    add(url, '原始线路（mpv）');
  } else if (proxyHls != null) {
    // 无扩展名的 /media：先试带 `.m3u8` 扩展名的同源地址。
    add(proxyHls, 'HLS 兼容线路');
    add(url, '原始线路');
  } else {
    add(url, '线路 1');
    if (hls != null) add(hls, 'HLS 兼容线路');
  }
  if (proxyHls != null && !seen.contains(proxyHls)) add(proxyHls, 'HLS 兼容线路');
  return result;
}
