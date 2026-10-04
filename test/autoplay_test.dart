/// 自动连播判定的回归测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/models/play_queue.dart';

void main() {
  group('shouldAutoAdvance', () {
    test('剧集模式 + 开关开 + 后面还有 → 连播', () {
      expect(
        shouldAutoAdvance(currentIndex: 0, total: 12, enabled: true, episodeList: true),
        isTrue,
      );
    });

    test('最后一集不连播', () {
      expect(
        shouldAutoAdvance(currentIndex: 11, total: 12, enabled: true, episodeList: true),
        isFalse,
      );
    });

    test('开关关掉就不连播', () {
      expect(
        shouldAutoAdvance(currentIndex: 0, total: 12, enabled: false, episodeList: true),
        isFalse,
      );
    });

    test('电影多线路（不是剧集）不连播 —— 自动跳会变成换线路', () {
      expect(
        shouldAutoAdvance(currentIndex: 0, total: 3, enabled: true, episodeList: false),
        isFalse,
      );
    });

    test('只有一条时没有「下一集」', () {
      expect(
        shouldAutoAdvance(currentIndex: 0, total: 1, enabled: true, episodeList: true),
        isFalse,
      );
      expect(
        shouldAutoAdvance(currentIndex: 0, total: 0, enabled: true, episodeList: true),
        isFalse,
      );
    });
  });
}
