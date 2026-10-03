/// 组件规范解析测试：用真实组件（happy-capy 的 51chigua / missav 片段）的字段形状做断言。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/models/capy_models.dart';
import 'package:splayer_mobile/runtime/widget_runtime.dart';
import 'package:splayer_mobile/store/plugin_store.dart';

import 'dart:convert';

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

  group('首页模块选择（红果/MissAV 第一个模块是搜索）', () {
    WidgetMeta build(List<Map<String, dynamic>> modules) =>
        WidgetMeta.fromJson(<String, dynamic>{'title': 'x', 'modules': modules});

    test('跳过搜索型模块，顺延到下一个', () {
      final meta = build(<Map<String, dynamic>>[
        <String, dynamic>{
          'title': '搜索短剧',
          'functionName': 'searchHongguo',
          'params': <dynamic>[
            <String, dynamic>{'name': 'keyword', 'type': 'input'},
          ],
        },
        <String, dynamic>{'title': '继续观看', 'functionName': 'getHongguoHistory'},
        <String, dynamic>{'title': '短剧', 'functionName': 'getHongguoShort'},
      ]);
      final picked = pickHomeModule(meta.modules);
      // 搜索被跳过；「继续观看」这类历史列表首屏必空，也跳过 → 落到真正的列表
      expect(picked?.functionName, 'getHongguoShort');
    });

    test('全是搜索型时退化为第一个，不返回空', () {
      final meta = build(<Map<String, dynamic>>[
        <String, dynamic>{'title': '搜索影片', 'functionName': 'searchVideos'},
      ]);
      expect(pickHomeModule(meta.modules)?.functionName, 'searchVideos');
    });

    test('正常组件取第一个模块', () {
      final meta = build(<Map<String, dynamic>>[
        <String, dynamic>{'title': '推荐', 'functionName': 'getProviderHome'},
        <String, dynamic>{'title': '最新', 'functionName': 'getProviderCategory'},
      ]);
      expect(pickHomeModule(meta.modules)?.functionName, 'getProviderHome');
    });

    test('识别搜索型：函数名带 search 或声明了关键词参数', () {
      final byName = WidgetMeta.fromJson(<String, dynamic>{
        'title': 'x',
        'modules': <dynamic>[
          <String, dynamic>{'title': '找片', 'functionName': 'searchProvider'},
        ],
      }).modules.single;
      final byParam = WidgetMeta.fromJson(<String, dynamic>{
        'title': 'x',
        'modules': <dynamic>[
          <String, dynamic>{
            'title': '找片',
            'functionName': 'doQuery',
            'params': <dynamic>[
              <String, dynamic>{'name': 'keyword', 'type': 'input'},
            ],
          },
        ],
      }).modules.single;
      expect(byName.looksLikeSearch, isTrue);
      expect(byParam.looksLikeSearch, isTrue);
    });

    test('搜索函数解析：优先用元数据声明，其次按模块猜', () {
      final declared = WidgetMeta.fromJson(<String, dynamic>{
        'title': 'x',
        'modules': <dynamic>[],
        'search': <String, dynamic>{'functionName': 'searchVideos'},
      });
      expect(declared.searchFunctionName, 'searchVideos');

      final guessed = WidgetMeta.fromJson(<String, dynamic>{
        'title': 'x',
        'modules': <dynamic>[
          <String, dynamic>{'title': '搜索短剧', 'functionName': 'searchHongguo'},
        ],
      });
      // 没有 search 段时，靠模块特征也能认出搜索函数
      expect(guessed.searchFunctionName, '');
      expect(guessed.modules.single.looksLikeSearch, isTrue);
      expect(pickHomeModule(guessed.modules)?.functionName, 'searchHongguo');
    });
  });

  group('桥接表达式编码（真机上「组件传入的是 null」的根因）', () {
    test('第三个实参必须是「承载 JSON 文本的 JS 字符串字面量」', () {
      final params = <String, dynamic>{'page': 1, 'serverUrl': 'https://happy-capy.garland.indevs.in'};
      final argumentJson = jsonEncode(params);
      final expression = buildInvokeExpression(
        entry: '__capyInvoke',
        callbackId: 'c1',
        functionName: 'getProviderHome',
        argumentJson: argumentJson,
      );

      // 期望形态：__capyInvoke("c1", "getProviderHome", "{\"page\":1,...}");
      expect(
        expression,
        equals('__capyInvoke("c1", "getProviderHome", ${jsonEncode(argumentJson)});'),
      );
      // 少一层编码（把 JSON 文本直接当 JS 字面量）就会长成这样，组件侧 JSON.parse 必抛
      expect(expression, isNot(contains(', $argumentJson);')));
    });

    test('字符串参数（loadDetail 的 link）同样要二次编码', () {
      const url = 'https://happy-capy.garland.indevs.in/api/v1/providers/hongguo/items/abc?x=1';
      final expression = buildInvokeExpression(
        entry: '__capyInvokeArg',
        callbackId: 'c2',
        functionName: 'loadDetail',
        argumentJson: jsonEncode(url),
      );
      expect(expression, equals('__capyInvokeArg("c2", "loadDetail", ${jsonEncode(jsonEncode(url))});'));
      // 还原链：JS 取到第三个字面量 → JSON.parse → 得到原 URL
      final literal = expression.substring(expression.indexOf('"loadDetail", ') + '"loadDetail", '.length);
      final jsString = jsonDecode(literal.replaceAll(RegExp(r'\);$'), '')) as String;
      expect(jsonDecode(jsString), url);
    });

    test('带引号与反斜杠的参数不会破坏表达式', () {
      final messy = <String, dynamic>{'keyword': '他说"hi"\\n', 'page': 1};
      final argumentJson = jsonEncode(messy);
      final expression = buildInvokeExpression(
        entry: '__capyInvoke',
        callbackId: 'c3',
        functionName: 'search',
        argumentJson: argumentJson,
      );
      final literal = expression.substring(expression.indexOf('"search", ') + '"search", '.length);
      final jsString = jsonDecode(literal.replaceAll(RegExp(r'\);$'), '')) as String;
      expect(jsonDecode(jsString), messy);
    });
  });
}
