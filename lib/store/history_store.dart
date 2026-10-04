/// 观看历史 / 播放进度记忆。
///
/// 落盘：`<appDocs>/history.json`（一个数组，按更新时间倒序使用）。
/// 每个「媒体 × 剧集」一条记录，存进度位置与总时长 —— 下次点进去就能续播。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 记录「在看什么」的定位信息（播放页需要它才能写进历史）。
@immutable
class WatchTarget {
  const WatchTarget({
    required this.pluginId,
    required this.mediaId,
    required this.title,
    this.posterUrl = '',
    this.link = '',
  });

  final String pluginId;

  /// 媒体级唯一 id（组件给的 `id`，缺失时退化为 link/标题）。
  final String mediaId;
  final String title;
  final String posterUrl;

  /// 详情链接（从历史回看时要用它重新 loadDetail）。
  final String link;

  /// 媒体级 key：同一部剧的所有集共享它。
  String get mediaKey => '$pluginId::$mediaId';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pluginId': pluginId,
        'mediaId': mediaId,
        'title': title,
        'posterUrl': posterUrl,
        'link': link,
      };

  factory WatchTarget.fromJson(Map<String, dynamic> json) => WatchTarget(
        pluginId: (json['pluginId'] ?? '').toString(),
        mediaId: (json['mediaId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        posterUrl: (json['posterUrl'] ?? '').toString(),
        link: (json['link'] ?? '').toString(),
      );
}

/// 剧集级 key：同一部剧的不同集各记一条，才能各自续播。
String watchEpisodeKey(WatchTarget target, String episodeTitle) =>
    episodeTitle.isEmpty ? target.mediaKey : '${target.mediaKey}::$episodeTitle';

class WatchRecord {
  WatchRecord({
    required this.key,
    required this.target,
    this.episodeTitle = '',
    this.positionMs = 0,
    this.durationMs = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String key;
  final WatchTarget target;
  final String episodeTitle;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  double get progress {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  /// 进度到 98% 以上算看完 —— 回看时从头开始，历史里标「已看完」。
  bool get finished => durationMs > 0 && positionMs >= durationMs * 0.98;

  bool get resumable => !finished && positionMs >= 5000;

  WatchRecord copyWith({int? positionMs, int? durationMs, DateTime? updatedAt}) => WatchRecord(
        key: key,
        target: target,
        episodeTitle: episodeTitle,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'target': target.toJson(),
        'episodeTitle': episodeTitle,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory WatchRecord.fromJson(Map<String, dynamic> json) => WatchRecord(
        key: (json['key'] ?? '').toString(),
        target: WatchTarget.fromJson(((json['target'] as Map?) ?? <String, dynamic>{}).cast<String, dynamic>()),
        episodeTitle: (json['episodeTitle'] ?? '').toString(),
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      );
}

class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();

  /// 保留上限，超出丢最旧的。
  static const int maxRecords = 500;

  final Map<String, WatchRecord> _byKey = <String, WatchRecord>{};
  bool _loaded = false;

  bool get loaded => _loaded;
  int get count => _byKey.length;

  /// 按最近观看倒序。
  List<WatchRecord> get records {
    final list = _byKey.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(list);
  }

  WatchRecord? find(String key) => _byKey[key];

  /// 某部剧最近在看的记录（详情页「继续观看」用）。
  ///
  /// 优先返回「可续播」的那条；都不可续播就退回最近一条（用于显示「已看完」）。
  WatchRecord? latestForMedia(String mediaKey) {
    final matched = _byKey.values.where((r) => r.key == mediaKey || r.key.startsWith('$mediaKey::')).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (matched.isEmpty) return null;
    for (final record in matched) {
      if (record.resumable) return record;
    }
    return matched.first;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map) continue;
            final record = WatchRecord.fromJson(entry.cast<String, dynamic>());
            if (record.key.isEmpty || record.target.title.isEmpty) continue;
            _byKey[record.key] = record;
          }
        }
      }
    } catch (e) {
      debugPrint('history.json 解析失败: $e');
    }
    notifyListeners();
  }

  /// 写入/更新一条进度。位置没变则不写盘（避免无意义的 IO）。
  Future<void> save(WatchRecord record) async {
    final previous = _byKey[record.key];
    if (previous != null &&
        previous.positionMs == record.positionMs &&
        previous.durationMs == record.durationMs) {
      return;
    }
    _byKey[record.key] = record;
    _prune();
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String key) async {
    if (_byKey.remove(key) == null) return;
    notifyListeners();
    await _persist();
  }

  Future<void> clear() async {
    if (_byKey.isEmpty) return;
    _byKey.clear();
    notifyListeners();
    await _persist();
  }

  void _prune() {
    if (_byKey.length <= maxRecords) return;
    final sorted = _byKey.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final record in sorted.skip(maxRecords)) {
      _byKey.remove(record.key);
    }
  }

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/history.json');
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(records.map((r) => r.toJson()).toList()));
    } catch (e) {
      debugPrint('history.json 写入失败: $e');
    }
  }
}
