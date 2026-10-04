/// 封面图请求头 与 详情 playerType 的回归测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/models/capy_models.dart';
import 'package:splayer_mobile/ui/poster_image.dart';

void main() {
  group('imageHeaders（封面图防盗链）', () {
    test('默认带浏览器 UA 与图片 Accept，不带 Referer', () {
      final h = imageHeaders('https://fourhoi.com/abc-123/cover-n.jpg');
      expect(h['User-Agent'], contains('Mozilla/5.0'));
      expect(h['Accept'], contains('image/'));
      expect(h.containsKey('Referer'), isFalse);
    });

    test('withReferer 时补同源 Referer（失败重试用）', () {
      final h = imageHeaders('https://spic2-1.71352.men/x/cover-n.jpg', withReferer: true);
      expect(h['Referer'], 'https://spic2-1.71352.men/');
    });

    test('非法 URL 不会写坏 Referer', () {
      final h = imageHeaders('not a url', withReferer: true);
      expect(h['Referer'], isNull);
    });
  });

  group('CapyDetail.playerType', () {
    test('解析详情里的 playerType（MissAV 列表项给 none、详情才给 system）', () {
      final detail = CapyDetail.fromJson(<String, dynamic>{
        'title': 'ABC-123',
        'videoUrl': 'https://backend/api/v1/subtitles/master.m3u8?videoUrl=x&player=mpv',
        'playerType': 'system',
      });
      expect(detail.playerType, 'system');
      expect(detail.videoUrl, contains('player=mpv'));
    });

    test('缺省时为空串（回落到列表项的声明）', () {
      final detail = CapyDetail.fromJson(<String, dynamic>{'title': 'x'});
      expect(detail.playerType, '');
    });
  });
}
