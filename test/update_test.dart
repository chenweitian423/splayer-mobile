/// 在线更新的版本比较测试（在线更新的核心判定）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/store/update_service.dart';

void main() {
  group('parseVersion', () {
    test('去掉 v 前缀', () {
      expect(parseVersion('v1.2.3'), <int>[1, 2, 3]);
    });

    test('忽略 build 号与后缀', () {
      expect(parseVersion('1.0.9+10'), <int>[1, 0, 9]);
      expect(parseVersion('1.0.9-beta.1'), <int>[1, 0, 9]);
    });

    test('位数不同也能比', () {
      expect(parseVersion('2.0'), <int>[2, 0]);
    });
  });

  group('isNewerVersion', () {
    test('常规升级', () {
      expect(isNewerVersion('v1.0.9', '1.0.8'), isTrue);
      expect(isNewerVersion('1.0.8', 'v1.0.8'), isFalse);
    });

    test('按数字比，不是按字符串比（1.0.10 > 1.0.9）', () {
      expect(isNewerVersion('1.0.10', '1.0.9'), isTrue);
      expect(isNewerVersion('1.0.9', '1.0.10'), isFalse);
    });

    test('进位比较', () {
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.1.0', '1.0.99'), isTrue);
      expect(isNewerVersion('1.0.0', '2.0.0'), isFalse);
    });

    test('位数不齐时短的一方补 0', () {
      expect(isNewerVersion('1.1', '1.0.9'), isTrue);
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
    });
  });
}
