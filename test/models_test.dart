/// 组件规范解析测试：用真实组件（happy-capy 的 51chigua / missav 片段）的字段形状做断言。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/models/capy_models.dart';
import 'package:splayer_mobile/store/plugin_store.dart';

void main() {
  group('WidgetMetadata 解析', () {
    test('title/name 与 icon/iconUrl 双写法都能吃', () {
      final meta = WidgetMeta.fromJson(<String, dynamic>{
        'name': '我的组件',
        'iconUrl': 'https://x/icon.ico',
        'version': '1.0.2',
        'globalParams': <dynamic>[
          <String, dynamic>{'name': 'serverUrl', 'type': 'input', 'value': 'https://backend'},
        ],
        'modules': <dynamic>[
          <String, dynamic>{'id': 'home', 'title': '最新', 'functionName': 'getProviderHome'},
        ],
      });
      expect(meta.title, '我的组件');
      expect(meta.icon, 'https://x/icon.ico');
      expect(meta.modules.single.functionName, 'getProviderHome');
      expect(meta.globalParams.single.name, 'serverUrl');
    });

    test('search 段单独摘出来', () {
      final meta = WidgetMeta.fromJson(<String, dynamic>{
        'title': 'x',
        'modules': <dynamic>[],
        'search': <String, dynamic>{'functionName': 'search'},
      });
      expect(meta.searchFunctionName, 'search');
    });
  });

  group('MediaItem 字段别名', () {
    test('posterUrl / posterPath / poster 任意一种都能取到图', () {
      for (final key in <String>['posterUrl', 'posterPath', 'poster_url', 'poster']) {
        final item = MediaItem.fromJson(<String, dynamic>{'id': '1', 'title': 't', key: 'https://img/p.jpg'});
        expect(item.posterUrl, 'https://img/p.jpg', reason: 'key=$key');
      }
    });

    test('id 或 title 全空时视为无效条目', () {
      expect(MediaItem.tryParse(<String, dynamic>{}), isNull);
      expect(MediaItem.listFrom(<dynamic>[<String, dynamic>{}, 'junk', null]).length, 0);
    });
  });

  group('loadDetail 返回结构', () {
    test('seasons/episodes 与 playSources 都能解析', () {
      final detail = CapyDetail.fromJson(<String, dynamic>{
        'title': '剧名',
        'mediaType': 'tv',
        'playSources': <dynamic>[
          <String, dynamic>{'title': '线路1', 'url': 'https://cdn/1.m3u8', 'isDefault': true},
        ],
        'seasons': <dynamic>[
          <String, dynamic>{
            'seasonNumber': 1,
            'episodes': <dynamic>[
              <String, dynamic>{'episodeNumber': 1, 'title': '第1集', 'mediaUrl': 'https://cdn/e1.m3u8'},
            ],
          },
        ],
      });
      expect(detail.playSources.single.videoUrl, 'https://cdn/1.m3u8');
      expect(detail.playSources.single.isDefault, isTrue);
      expect(detail.allEpisodes.single.videoUrl, 'https://cdn/e1.m3u8');
      expect(detail.allEpisodes.single.title, '第1集');
    });

    test('单季 episodeItems 结构', () {
      final detail = CapyDetail.fromJson(<String, dynamic>{
        'title': 'x',
        'episodeItems': <dynamic>[
          <String, dynamic>{'id': 'e1', 'episodeNumber': 3, 'videoUrl': 'https://cdn/e3.m3u8'},
        ],
      });
      expect(detail.allEpisodes.single.episodeNumber, 3);
      expect(detail.allEpisodes.single.title, '第 3 集');
    });
  });

  group('托管页扫描正则', () {
    test('能从页面 HTML 里挑出 .js 链接', () {
      const html = '<script src="https://a/b/widgets/51chigua.js"></script>'
          "<a href='/widgets/dsd.js?v=2'>x</a>"
          '<img src="cover.png">';
      final found = kJsLinkPattern.allMatches(html).map((m) => m.group(1)).toList();
      expect(found, contains('https://a/b/widgets/51chigua.js'));
      expect(found, contains('/widgets/dsd.js?v=2'));
      expect(found.any((f) => f!.endsWith('.png')), isFalse);
    });
  });
}
