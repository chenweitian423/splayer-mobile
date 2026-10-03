/// 组件仓库：落盘、导入、启停。
///
/// 落盘结构（对齐 SPlayer 的 pluginsDir + plugins_json 思路）：
///
/// ```text
/// <appDocs>/plugins/plugins.json     组件清单
/// <appDocs>/plugins/<id>.js          组件源码快照
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../runtime/widget_runtime.dart';

/// 从托管页里挑 js 的正则（与 SPlayer dex 里的实现一致）。
final RegExp kJsLinkPattern = RegExp("[\"']([^\"'\\s<>]+?\\.js(?:\\?[^\"'\\s<>]*)?)[\"']");

class PluginRecord {
  PluginRecord({
    required this.id,
    required this.title,
    required this.version,
    required this.source,
    this.sourceUrl = '',
    this.icon = '',
    this.enabled = true,
    this.addedAt,
    this.lastError = '',
  });

  final String id;
  String title;
  String version;
  String source;
  String sourceUrl;
  String icon;
  bool enabled;
  DateTime? addedAt;
  String lastError;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'version': version,
        'sourceUrl': sourceUrl,
        'icon': icon,
        'enabled': enabled,
        'addedAt': (addedAt ?? DateTime.now()).toIso8601String(),
        'lastError': lastError,
      };

  factory PluginRecord.fromJson(Map<String, dynamic> json, String source) {
    return PluginRecord(
      id: json['id'].toString(),
      title: (json['title'] ?? '未命名组件').toString(),
      version: (json['version'] ?? '1.0.0').toString(),
      source: source,
      sourceUrl: (json['sourceUrl'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      enabled: json['enabled'] != false,
      addedAt: DateTime.tryParse((json['addedAt'] ?? '').toString()),
      lastError: (json['lastError'] ?? '').toString(),
    );
  }
}

class HostPageCandidate {
  HostPageCandidate({required this.url, required this.valid, this.title = '', this.error = ''});

  final String url;
  final bool valid;
  final String title;
  final String error;
}

class PluginStore extends ChangeNotifier {
  PluginStore._();

  static final PluginStore instance = PluginStore._();

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final List<PluginRecord> _records = <PluginRecord>[];
  Directory? _dir;

  List<PluginRecord> get records => List.unmodifiable(_records);
  List<PluginRecord> get enabledRecords => _records.where((r) => r.enabled).toList();

  Future<Directory> _pluginDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/plugins');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<void> load() async {
    final dir = await _pluginDir();
    final manifest = File('${dir.path}/plugins.json');
    _records.clear();
    if (await manifest.exists()) {
      try {
        final decoded = jsonDecode(await manifest.readAsString());
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map) continue;
            final map = entry.cast<String, dynamic>();
            final id = map['id']?.toString() ?? '';
            if (id.isEmpty) continue;
            final file = File('${dir.path}/$id.js');
            if (!await file.exists()) continue;
            _records.add(PluginRecord.fromJson(map, await file.readAsString()));
          }
        }
      } catch (e) {
        debugPrint('plugins.json 解析失败: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final dir = await _pluginDir();
    final manifest = File('${dir.path}/plugins.json');
    await manifest.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_records.map((r) => r.toJson()).toList()),
    );
  }

  Future<void> _writeSource(PluginRecord record) async {
    final dir = await _pluginDir();
    await File('${dir.path}/${record.id}.js').writeAsString(record.source);
  }

  String _slugFrom(String url, {String fallback = 'plugin'}) {
    final name = Uri.tryParse(url)?.pathSegments.last ?? '';
    var slug = name.replaceAll(RegExp(r'\.js.*$'), '');
    slug = slug.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (slug.isEmpty) slug = '$fallback-${DateTime.now().millisecondsSinceEpoch}';
    return slug;
  }

  /// 从网络地址导入（也支持直接粘贴整段 js 源码）。
  Future<PluginRecord> importFromUrl(String rawUrl) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw RuntimeException('地址无效，需要 http/https 开头的 js 直链');
    }
    final response = await http.get(uri, headers: <String, String>{'User-Agent': _userAgent});
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw RuntimeException('下载失败：HTTP ${response.statusCode}');
    }
    final source = utf8.decode(response.bodyBytes, allowMalformed: true);
    return importSource(source, sourceUrl: url, preferredId: _slugFrom(url));
  }

  /// 导入一段 js 源码。
  Future<PluginRecord> importSource(String source, {String sourceUrl = '', String preferredId = ''}) async {
    if (!source.contains('WidgetMetadata')) {
      throw RuntimeException('这个地址不是组件脚本（未找到 WidgetMetadata）');
    }
    final metaJson = _extractMeta(source);
    var id = preferredId.isNotEmpty ? preferredId : _slugFrom(sourceUrl, fallback: 'plugin');
    final duplicate = _records.indexWhere((r) => r.id == id);
    final record = PluginRecord(
      id: id,
      title: metaJson?['title']?.toString() ?? id,
      version: metaJson?['version']?.toString() ?? '1.0.0',
      source: source,
      sourceUrl: sourceUrl,
      icon: (metaJson?['icon'] ?? metaJson?['iconUrl'] ?? '').toString(),
      addedAt: DateTime.now(),
    );
    if (duplicate >= 0) {
      _records[duplicate] = record;
    } else {
      _records.add(record);
    }
    await _writeSource(record);
    await _persist();
    notifyListeners();
    return record;
  }

  /// 轻量提取 WidgetMetadata（不跑 JS，正则抓字段够用）。
  Map<String, dynamic>? _extractMeta(String source) {
    try {
      final start = source.indexOf('WidgetMetadata');
      if (start < 0) return null;
      final brace = source.indexOf('{', start);
      if (brace < 0) return null;
      var depth = 0;
      for (var i = brace; i < source.length; i++) {
        final ch = source[i];
        if (ch == '{') depth++;
        if (ch == '}') {
          depth--;
          if (depth == 0) {
            final slice = source.substring(brace, i + 1);
            final decoded = _looseJson(slice);
            return decoded;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _looseJson(String text) {
    // 先按标准 JSON 试；失败则退化为字段级正则
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    final out = <String, dynamic>{};
    for (final key in <String>['id', 'title', 'name', 'version', 'icon', 'iconUrl', 'description', 'site']) {
      final match = RegExp('$key\\s*:\\s*["\']([^"\']*)["\']').firstMatch(text);
      if (match != null) out[key] = match.group(1);
    }
    return out.isEmpty ? null : out;
  }

  Future<void> setEnabled(PluginRecord record, bool enabled) async {
    record.enabled = enabled;
    await _persist();
    notifyListeners();
  }

  Future<void> remove(PluginRecord record) async {
    _records.removeWhere((r) => r.id == record.id);
    final dir = await _pluginDir();
    final file = File('${dir.path}/${record.id}.js');
    if (await file.exists()) await file.delete();
    await _persist();
    notifyListeners();
  }

  Future<void> markError(PluginRecord record, String error) async {
    record.lastError = error;
    await _persist();
    notifyListeners();
  }

  /// 扫「组件托管页」：把页面上出现过的全部 .js 列出来并逐个验证。
  Future<List<HostPageCandidate>> scanHostPage(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw RuntimeException('托管页地址无效');
    }
    final response = await http.get(uri, headers: <String, String>{'User-Agent': _userAgent});
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw RuntimeException('托管页打不开：HTTP ${response.statusCode}');
    }
    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final links = <String>{};
    for (final match in kJsLinkPattern.allMatches(html)) {
      final raw = match.group(1) ?? '';
      if (raw.isEmpty || raw.startsWith('data:')) continue;
      final resolved = uri.resolve(raw).toString();
      links.add(resolved);
    }
    final list = links.toList();
    final results = <HostPageCandidate>[];
    const batchSize = 4;
    for (var i = 0; i < list.length; i += batchSize) {
      final batch = list.sublist(i, i + batchSize > list.length ? list.length : i + batchSize);
      final settled = await Future.wait(batch.map(_probe));
      results.addAll(settled);
    }
    results.sort((a, b) {
      if (a.valid != b.valid) return a.valid ? -1 : 1;
      return a.url.compareTo(b.url);
    });
    return results;
  }

  Future<HostPageCandidate> _probe(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: <String, String>{'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 10));
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final valid = response.statusCode >= 200 && response.statusCode < 400 && body.contains('WidgetMetadata');
      final titleMatch = RegExp("title\\s*:\\s*[\"']([^\"']{1,40})[\"']").firstMatch(body);
      return HostPageCandidate(
        url: url,
        valid: valid,
        title: titleMatch?.group(1) ?? '',
        error: valid ? '' : '不是组件脚本',
      );
    } catch (e) {
      return HostPageCandidate(url: url, valid: false, error: '$e');
    }
  }
}
