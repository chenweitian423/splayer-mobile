/// 播放候选地址生成的回归测试。
///
/// 背景（真机日志 + 实测）：
///   * 后端播放代理 `/api/v1/playback/<token>/media` 实际下发的是 **HLS 清单**
///     （`Content-Type: application/vnd.apple.mpegurl`，与 `/playlist.m3u8` 字节相同）；
///   * 但它没有扩展名 → Android 的 ExoPlayer 认成未知格式，
///     报 `ExoPlaybackException: Source error`；iOS 的 AVPlayer 会嗅探内容所以能播。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/models/play_queue.dart';

const String _token =
    'eyJjIjpudWxsLCJleHAiOjE3OTExMzUxNjAsInAiOiJ5ZWd1byIsInEiOm51bGwsInIiOiJbXCIzMzk1XCIsXCIxODY2MzlcIl0ifQ'
    '.pOWVuB63ClWUm9ghxHc4hwt9x4NMjFudFvB4divj_Ho';
const String _proxyMedia = 'https://happy-capy.garland.indevs.in/api/v1/playback/$_token/media';

void main() {
  group('rewriteBackendPlaybackToHls', () {
    test('把 /media 换成同源 /playlist.m3u8', () {
      expect(
        rewriteBackendPlaybackToHls(_proxyMedia),
        'https://happy-capy.garland.indevs.in/api/v1/playback/$_token/playlist.m3u8',
      );
    });

    test('token 逐字保留（动一个字节签名就废）', () {
      final out = rewriteBackendPlaybackToHls(_proxyMedia)!;
      expect(out.contains(_token), isTrue);
      expect(out.substring(0, out.lastIndexOf('/')), startsWith('https://happy-capy.garland.indevs.in/api/v1/playback/'));
    });

    test('保留查询串', () {
      expect(
        rewriteBackendPlaybackToHls('$_proxyMedia?x=1&y=2'),
        'https://happy-capy.garland.indevs.in/api/v1/playback/$_token/playlist.m3u8?x=1&y=2',
      );
    });

    test('已经是 .m3u8 / 其它地址 → 不改', () {
      expect(rewriteBackendPlaybackToHls('https://a.com/api/v1/playback/tok/playlist.m3u8'), isNull);
      expect(rewriteBackendPlaybackToHls('https://cdn.com/a/b/c.mp4'), isNull);
      expect(rewriteBackendPlaybackToHls('https://cdn.com/live/master.m3u8?player=hls'), isNull);
      expect(rewriteBackendPlaybackToHls(''), isNull);
    });
  });

  group('playUrlCandidates', () {
    test('后端代理地址：HLS 兼容线路排第一，原始地址兜底', () {
      final list = playUrlCandidates(_proxyMedia);
      expect(list.length, 2);
      expect(list.first.url, endsWith('/playlist.m3u8'));
      expect(list.first.label, 'HLS 兼容线路');
      expect(list.last.url, _proxyMedia);
    });

    test('mpv 变体仍按老规则先试 hls', () {
      final list = playUrlCandidates('https://cdn.com/v?player=mpv&id=1');
      expect(list.first.url, 'https://cdn.com/v?player=hls&id=1');
    });

    test('普通直链只给一条候选（不无中生有）', () {
      final list = playUrlCandidates('https://cdn.com/a/master.m3u8');
      expect(list.length, 1);
      expect(list.single.url, 'https://cdn.com/a/master.m3u8');
    });

    test('请求头透传到每条候选', () {
      final list = playUrlCandidates(_proxyMedia, headers: <String, String>{'Referer': 'https://x.com/'});
      expect(list.every((c) => c.headers['Referer'] == 'https://x.com/'), isTrue);
    });
  });
}
