/// 屏幕自适应度量的回归测试（断点与夹取区间）。
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/ui/layout.dart';

void main() {
  group('导航断点', () {
    test('窄屏用底部导航栏，宽屏（>=600）用左侧导航栏', () {
      expect(useNavigationRail(360), isFalse);
      expect(useNavigationRail(599), isFalse);
      expect(useNavigationRail(kRailBreakpoint), isTrue);
      expect(useNavigationRail(1024), isTrue);
    });

    test('判断横屏', () {
      expect(isLandscape(const Size(800, 400)), isTrue);
      expect(isLandscape(const Size(400, 800)), isFalse);
      expect(isLandscape(const Size(600, 600)), isFalse);
    });
  });

  group('海报行度量', () {
    test('竖屏大屏顶部夹到上限，不会把海报拉太大', () {
      expect(posterRowHeight(900), 210.0);
      expect(posterRowHeight(2000), 210.0);
    });

    test('横屏矮屏收缩到下限，不会占掉大半个屏幕', () {
      expect(posterRowHeight(400), 150.0);
      expect(posterRowHeight(300), 150.0);
    });

    test('中间区间按 34% 线性取值', () {
      expect(posterRowHeight(500), closeTo(170.0, 0.01));
    });

    test('卡片宽度由行高反推并夹取', () {
      expect(posterCardWidth(210), closeTo(121.33, 0.01));
      expect(posterCardWidth(150), 88.0); // 反推值 81.3 < 下限
      expect(posterCardWidth(1000), 140.0); // 超过上限
    });

    test('网格海报在大屏上给更大的边长', () {
      expect(posterGridExtent(400), 140.0);
      expect(posterGridExtent(900), 168.0);
      expect(posterGridExtent(1400), 168.0);
    });
  });
}
