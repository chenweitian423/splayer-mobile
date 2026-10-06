/// 组件导入链路：托管页候选地址 + 深链还原。
///
/// 背景（2026-10-07 真机现象「/ext/ 里的 js 添加上都不行」）：
/// happy-capy 的 `/ext/` 托管页数据里只写裸文件名（`"file": "ALLINONE.js"`），
/// 真实地址是页面 JS 现拼的 `<origin>/widgets/ALLINONE.js`。
/// 只按「页面相对路径」拼会全部落到 `/ext/xxx.js` → 实测 47 个引用 100% 404。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/store/plugin_store.dart';

String _deepLink(String target) {
  final token = base64Url.encode(utf8.encode(target)).replaceAll('=', '');
  return 'com.feifeiduck.capyplayer://add-widget?data=$token';
}

void main() {
  group('深链还原', () {
    test('add-widget 深链解出真正的 js 直链', () {
      const target = 'http://192.168.123.80:8788/widgets/ALLINONE.js';
      expect(resolveWidgetDeepLink(_deepLink(target)), target);
      expect(looksLikeWidgetUrl(_deepLink(target)), isTrue);
    });

    test('带路径的深链也能还原', () {
      const target = 'https://example.com/a/b/x.js?v=2';
      expect(resolveWidgetDeepLink(_deepLink(target)), target);
    });

    test('http(s) 直链原样返回（不会被当成 base64 解坏）', () {
      const url = 'https://example.com/widgets/x.js?data=aGVsbG8';
      expect(resolveWidgetDeepLink(url), url);
      expect(looksLikeWidgetUrl(url), isTrue);
    });

    test('解出来不是 http(s) 就放弃还原', () {
      final token = base64Url.encode(utf8.encode('hello')).replaceAll('=', '');
      final link = 'com.feifeiduck.capyplayer://add-widget?data=$token';
      expect(resolveWidgetDeepLink(link), link);
      expect(looksLikeWidgetUrl(link), isFalse);
    });

    test('普通文本不受影响', () {
      const junk = 'var WidgetMetadata = { id: "x" }';
      expect(resolveWidgetDeepLink(junk), junk);
      expect(looksLikeWidgetUrl(junk), isFalse);
    });
  });

  group('托管页候选地址', () {
    test('裸文件名回退到同源 /widgets/', () {
      final page = Uri.parse('http://192.168.123.80:8788/ext/');
      expect(widgetCandidateUrls(page, 'ALLINONE.js'), <String>[
        'http://192.168.123.80:8788/ext/ALLINONE.js',
        'http://192.168.123.80:8788/widgets/ALLINONE.js',
      ]);
    });

    test('页面挂在子路径上时回退仍打到站点根', () {
      final page = Uri.parse('https://h/sub/dir/page.html');
      expect(widgetCandidateUrls(page, 'x.js'), <String>[
        'https://h/sub/dir/x.js',
        'https://h/widgets/x.js',
      ]);
    });

    test('带路径的引用不猜目录', () {
      final page = Uri.parse('http://h/ext/');
      expect(widgetCandidateUrls(page, 'a/b.js'), <String>['http://h/ext/a/b.js']);
      expect(widgetCandidateUrls(page, '/js/x.js'), <String>['http://h/js/x.js']);
    });

    test('空引用返回空列表', () {
      expect(widgetCandidateUrls(Uri.parse('http://h/ext/'), '   '), isEmpty);
    });
  });

  group('扫描正则', () {
    test('能从托管页数据里抓出裸文件名', () {
      const html = 'const DATA = {"cats":[["影视聚合",[{"file": "ALLINONE.js", "id": "x"}]]]};';
      final found = kJsLinkPattern.allMatches(html).map((m) => m.group(1)).toList();
      expect(found, <String>['ALLINONE.js']);
    });
  });
}
