/// HLS 中转的清单改写测试（纯函数，播放兼容中转的核心）。
///
/// 背景：后端只代理清单，清单里的分片/密钥直指轮换的第三方 CDN，
/// 其中部分主机连接要 10 秒 —— ExoPlayer 超时即报 Source error，
/// 而 iOS 更有耐心所以能播。中转把分片/密钥改走本机，由 App 自己带长超时去拉。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/playback/hls_relay.dart';

String _wrap(String u) => 'WRAP($u)';

void main() {
  const manifestUrl = 'https://host/api/v1/playback/tok/playlist.m3u8';

  test('分片绝对地址被包裹，相对地址按清单地址解析', () {
    const src = '''
#EXTM3U
#EXT-X-VERSION:3
#EXTINF:5.000,
https://cdn-a.com/a0.ts?k=1
#EXTINF:5.000,
seg1.ts
''';
    final out = rewriteHlsManifest(src, manifestUrl, _wrap);
    expect(out, contains('WRAP(https://cdn-a.com/a0.ts?k=1)'));
    expect(out, contains('WRAP(https://host/api/v1/playback/tok/seg1.ts)'));
  });

  test('AES-128 的 EXT-X-KEY URI 也要被包裹（拿不到密钥就播不了）', () {
    const src = '#EXT-X-KEY:METHOD=AES-128,URI="https://cdn-b.com/crypt.key?auth=1",IV=0x1\n';
    final out = rewriteHlsManifest(src, manifestUrl, _wrap);
    expect(out, contains('URI="WRAP(https://cdn-b.com/crypt.key?auth=1)"'));
    expect(out, contains('METHOD=AES-128'));
    expect(out, contains('IV=0x1'));
  });

  test('EXT-X-MAP / EXT-X-MEDIA 里的 URI 一并处理', () {
    const src = '''
#EXT-X-MAP:URI="init.mp4"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",URI="audio.m3u8"
''';
    final out = rewriteHlsManifest(src, manifestUrl, _wrap);
    expect(out, contains('URI="WRAP(https://host/api/v1/playback/tok/init.mp4)"'));
    expect(out, contains('URI="WRAP(https://host/api/v1/playback/tok/audio.m3u8)"'));
  });

  test('其它 # 标签与空行原样保留', () {
    const src = '#EXTM3U\n\n#EXT-X-TARGETDURATION:6\n#EXT-X-ENDLIST\n';
    final out = rewriteHlsManifest(src, manifestUrl, _wrap);
    expect(out, contains('#EXTM3U'));
    expect(out, contains('#EXT-X-TARGETDURATION:6'));
    expect(out, contains('#EXT-X-ENDLIST'));
  });

  test('looksLikeHls：认 .m3u8，也认后端无扩展名的 /media', () {
    expect(HlsRelay.looksLikeHls('https://a.com/x/master.m3u8'), isTrue);
    expect(HlsRelay.looksLikeHls('https://h/api/v1/playback/tok/media'), isTrue);
    expect(HlsRelay.looksLikeHls('https://cdn.com/v.mp4'), isFalse);
    expect(HlsRelay.looksLikeHls('https://h/api/v1/playback/tok/key'), isFalse);
  });
}
