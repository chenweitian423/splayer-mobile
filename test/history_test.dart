/// 观看历史 / 播放进度记忆的纯逻辑测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:splayer_mobile/store/history_store.dart';

WatchTarget _target() => const WatchTarget(
      pluginId: 'capy.backend.51chigua',
      mediaId: 'abc-123',
      title: '测试影片',
      posterUrl: 'https://example.com/p.jpg',
      link: 'https://example.com/detail/abc-123',
    );

WatchRecord _record({int position = 12_000, int duration = 100_000, String episode = ''}) => WatchRecord(
      key: watchEpisodeKey(_target(), episode),
      target: _target(),
      episodeTitle: episode,
      positionMs: position,
      durationMs: duration,
    );

void main() {
  group('watchEpisodeKey', () {
    test('无剧集时退化为媒体级 key（同一部剧共享）', () {
      expect(watchEpisodeKey(_target(), ''), 'capy.backend.51chigua::abc-123');
    });

    test('有剧集时按集分开，各自续播', () {
      final first = watchEpisodeKey(_target(), '第 1 集');
      final second = watchEpisodeKey(_target(), '第 2 集');
      expect(first, isNot(second));
      expect(first.startsWith(_target().mediaKey), isTrue);
    });
  });

  group('WatchRecord 进度语义', () {
    test('progress 是比例并夹在 0~1', () {
      expect(_record(position: 25_000, duration: 100_000).progress, 0.25);
      expect(_record(position: 200_000, duration: 100_000).progress, 1.0);
      expect(_record(position: 1000, duration: 0).progress, 0.0);
    });

    test('progress 达到 98% 算看完', () {
      expect(_record(position: 97_000, duration: 100_000).finished, isFalse);
      expect(_record(position: 98_000, duration: 100_000).finished, isTrue);
    });

    test('刚开头（<5 秒）不值得续播，看完的也不续播', () {
      expect(_record(position: 3_000).resumable, isFalse);
      expect(_record(position: 30_000).resumable, isTrue);
      expect(_record(position: 99_000, duration: 100_000).resumable, isFalse);
    });
  });

  group('序列化', () {
    test('JSON 往返保留定位信息与进度', () {
      final source = _record(position: 42_000, duration: 120_000, episode: '第 3 集');
      final restored = WatchRecord.fromJson(source.toJson());
      expect(restored.key, source.key);
      expect(restored.target.pluginId, 'capy.backend.51chigua');
      expect(restored.target.mediaId, 'abc-123');
      expect(restored.target.link, 'https://example.com/detail/abc-123');
      expect(restored.episodeTitle, '第 3 集');
      expect(restored.positionMs, 42_000);
      expect(restored.durationMs, 120_000);
    });

    test('缺字段时不炸（旧版本数据）', () {
      final restored = WatchRecord.fromJson(<String, dynamic>{'key': 'k', 'target': <String, dynamic>{'title': 't'}});
      expect(restored.key, 'k');
      expect(restored.positionMs, 0);
      expect(restored.progress, 0);
    });
  });
}
