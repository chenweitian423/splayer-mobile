/// 组件运行时：一个 WebView 沙箱 = 一个组件的执行环境。
///
/// 设计要点（对齐 SPlayer / CapyPlayer 的运行时契约）：
///   * JS 侧只有 window.Widget，所有 IO 都通过 CapyBridge 桥回原生；
///   * 原生 -> JS 用 runJavaScript 把结果回灌（__capyHttpResult / __capyReject）；
///   * 每个组件一个独立 WebView，避免 SPlayer 那种"所有插件共用一个上下文、
///     同名内部函数互相覆盖"的问题。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../models/capy_models.dart';
import '../store/plugin_store.dart';

const String kBridgeName = 'CapyBridge';
const String kRuntimeBaseUrl = 'https://capy.local/';
const String kDefaultUserAgent =
    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

class RuntimeException implements Exception {
  RuntimeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一个已装载的组件。
class WidgetRuntime {
  WidgetRuntime(this.record);

  final PluginRecord record;

  final WebViewController _controller = WebViewController();
  final Completer<void> _shellReady = Completer<void>();
  final Map<String, Completer<dynamic>> _pending = <String, Completer<dynamic>>{};

  WidgetMeta? _meta;
  bool _booted = false;
  String? _lastError;
  int _seq = 0;
  bool _disposed = false;

  WidgetMeta? get meta => _meta;
  String? get lastError => _lastError;
  bool get isBooted => _booted;

  static String? _jquerySource;
  static String? _runtimeSource;
  static final http.Client _client = http.Client();

  Widget buildView({double size = 260}) {
    return SizedBox(
      width: size,
      height: size,
      child: WebViewWidget(controller: _controller),
    );
  }

  Future<void> boot() async {
    if (_booted) return;
    _jquerySource ??= await rootBundle.loadString('assets/runtime/jquery.min.js');
    _runtimeSource ??= await rootBundle.loadString('assets/runtime/capy_runtime.js');

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(kDefaultUserAgent)
      ..addJavaScriptChannel(kBridgeName, onMessageReceived: _onBridgeMessage);

    final shell = _buildShell();
    await _controller.loadHtmlString(shell, baseUrl: kRuntimeBaseUrl);

    try {
      await _shellReady.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      throw RuntimeException('运行时初始化超时（WebView 未就绪）');
    }

    // 组件源码在运行时之后注入，保证 window.Widget 已存在
    try {
      await _controller.runJavaScript(record.source);
    } catch (e) {
      throw RuntimeException('组件脚本注入失败：$e');
    }

    final metaJson = await _evalString('__capyMetadata()');
    if (metaJson == null || metaJson == 'null' || metaJson.isEmpty) {
      throw RuntimeException('该脚本未声明全局 WidgetMetadata');
    }
    final decoded = jsonDecode(metaJson);
    if (decoded is! Map) {
      throw RuntimeException('WidgetMetadata 解析失败');
    }
    _meta = WidgetMeta.fromJson(decoded.cast<String, dynamic>());
    if (_meta!.modules.isEmpty && _meta!.searchFunctionName.isEmpty) {
      throw RuntimeException('WidgetMetadata 里没有任何可用模块');
    }
    _booted = true;
  }

  /// WebView 外壳：先注入 jQuery（Widget.html 的 DOM 引擎）与运行时，
  /// 组件源码由 boot() 在运行时之后单独注入。
  String _buildShell() {
    final buffer = StringBuffer()
      ..writeln('<!DOCTYPE html><html><head><meta charset="utf-8">')
      ..writeln('<script>window.__CAPY_PLUGIN_ID__=${jsonEncode(record.id)};</script>')
      ..writeln('<script>')
      ..writeln(_jquerySource)
      ..writeln('</script>')
      ..writeln('<script>')
      ..writeln(_runtimeSource)
      ..writeln('</script>')
      ..writeln('</head><body></body></html>');
    return buffer.toString();
  }

  /// 计算参数默认值：globalParams 兜底 + 模块常量参数。
  Map<String, dynamic> buildParams(CapyModule module, {Map<String, dynamic> overrides = const {}}) {
    final params = <String, dynamic>{};
    for (final p in _meta?.globalParams ?? const <CapyParam>[]) {
      params[p.name] = p.defaultValue;
    }
    for (final p in module.params) {
      switch (p.type) {
        case 'page':
          params[p.name] = 1;
          break;
        case 'offset':
          params[p.name] = 0;
          break;
        case 'count':
          params[p.name] = 20;
          break;
        default:
          params[p.name] = p.defaultValue;
      }
    }
    params.addAll(overrides);
    params.removeWhere((key, value) => value == null);
    return params;
  }

  Future<dynamic> _invoke(String functionName, Map<String, dynamic> params) async {
    if (!_booted) throw RuntimeException('组件未装载：${record.title}');
    final cbId = 'c${++_seq}';
    final completer = Completer<dynamic>();
    _pending[cbId] = completer;
    final payload = jsonEncode(params);
    await _controller.runJavaScript(
      '__capyInvoke(${jsonEncode(cbId)}, ${jsonEncode(functionName)}, ${jsonEncode(payload)});',
    );
    final result = await completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(cbId);
        throw RuntimeException('调用 $functionName 超时');
      },
    );
    return result;
  }

  Future<List<MediaItem>> callList(CapyModule module, {Map<String, dynamic> overrides = const {}}) async {
    final raw = await _invoke(module.functionName, buildParams(module, overrides: overrides));
    if (raw is Map && raw['ok'] == false) {
      throw RuntimeException(_errorText(raw));
    }
    final data = raw is Map && raw.containsKey('data') ? raw['data'] : raw;
    return MediaItem.listFrom(data);
  }

  Future<List<MediaItem>> search(String keyword, {int page = 1}) async {
    final fn = _meta?.searchFunctionName.isNotEmpty == true ? _meta!.searchFunctionName : 'search';
    final params = <String, dynamic>{'keyword': keyword, 'query': keyword, 'wd': keyword, 'page': page};
    for (final p in _meta?.globalParams ?? const <CapyParam>[]) {
      params[p.name] = p.defaultValue;
    }
    final raw = await _invoke(fn, params);
    if (raw is Map && raw['ok'] == false) throw RuntimeException(_errorText(raw));
    final data = raw is Map && raw.containsKey('data') ? raw['data'] : raw;
    return MediaItem.listFrom(data);
  }

  Future<CapyDetail> loadDetail(String link) async {
    final raw = await _invoke('loadDetail', <String, dynamic>{'link': link, 'url': link, 'id': link});
    if (raw is Map && raw['ok'] == false) throw RuntimeException(_errorText(raw));
    final data = raw is Map && raw.containsKey('data') ? raw['data'] : raw;
    if (data is Map) {
      return CapyDetail.fromJson(data.cast<String, dynamic>());
    }
    if (data is List) {
      // 顶层数组 = 同一影片的多条线路
      final sources = <PlaySource>[];
      for (var i = 0; i < data.length; i++) {
        final e = data[i];
        if (e is Map) sources.add(PlaySource.fromJson(e.cast<String, dynamic>(), i));
      }
      return CapyDetail(title: '', playSources: sources);
    }
    throw RuntimeException('loadDetail 返回结构无法解析');
  }

  String _errorText(Map raw) {
    final data = raw['data'];
    if (data is Map && data['error'] != null) return data['error'].toString();
    return raw['error']?.toString() ?? '调用失败';
  }

  /// 运行诊断：元数据 + 各模块函数是否存在。
  Future<Map<String, dynamic>?> diagnose() async {
    final text = await _evalString('__capyDiagnose()');
    if (text == null || text == 'null') return null;
    final decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }

  Future<String?> _evalString(String expression) async {
    try {
      final result = await _controller.runJavaScriptReturningResult(expression);
      return _normalizeJsResult(result);
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  /// Android 的 evaluateJavascript 返回 JSON 编码串（带引号），iOS 返回裸值。
  static String? _normalizeJsResult(dynamic result) {
    if (result == null) return null;
    if (result is String) {
      if (result.length >= 2 && result.startsWith('"') && result.endsWith('"')) {
        try {
          final decoded = jsonDecode(result);
          if (decoded is String) return decoded;
        } catch (_) {}
      }
      return result;
    }
    return result.toString();
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      payload = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (payload['type']) {
      case 'ready':
        if (!_shellReady.isCompleted) _shellReady.complete();
        break;
      case 'log':
        debugPrint('[capy:${record.title}] ${payload['level']}: ${payload['message']}');
        break;
      case 'http':
        unawaited(_handleHttp(payload));
        break;
      case 'result':
        final cbId = payload['cbId']?.toString() ?? '';
        final completer = _pending.remove(cbId);
        if (completer != null && !completer.isCompleted) {
          final text = payload['payload']?.toString();
          if (text == null || text.isEmpty) {
            completer.complete(<String, dynamic>{'ok': false, 'error': 'empty payload'});
          } else {
            try {
              completer.complete(jsonDecode(text));
            } catch (e) {
              completer.complete(<String, dynamic>{'ok': false, 'error': 'bad payload: $e'});
            }
          }
        }
        break;
    }
  }

  Future<void> _handleHttp(Map<String, dynamic> payload) async {
    final cbId = payload['cbId']?.toString() ?? '';
    final method = (payload['method']?.toString() ?? 'GET').toUpperCase();
    final url = payload['url']?.toString() ?? '';
    final options = (payload['options'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    Map<String, dynamic> reply;
    try {
      reply = await _performRequest(method, url, options);
    } catch (e) {
      reply = <String, dynamic>{'transportError': true, 'error': '$e', 'status': 0, 'data': ''};
    }
    if (_disposed) return;
    try {
      await _controller.runJavaScript(
        '__capyHttpResult(${jsonEncode(cbId)}, ${jsonEncode(jsonEncode(reply))});',
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _performRequest(String method, String url, Map<String, dynamic> options) async {
    final uri = _buildUri(url, options['params']);
    final body = options['body'];
    final timeoutMs = (options['timeout'] as num?)?.toInt() ?? 30000;

    final request = http.Request(method, uri);
    request.followRedirects = options['allowRedirects'] != false;
    request.headers['User-Agent'] = kDefaultUserAgent;
    request.headers['Accept'] = '*/*';
    request.headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    final headers = (options['headers'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    headers.forEach((key, value) {
      final name = key.trim();
      if (name.isNotEmpty) request.headers[name] = value?.toString() ?? '';
    });
    if (body is String && body.isNotEmpty) {
      request.body = body;
      if (!request.headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
        request.headers['Content-Type'] = 'application/json; charset=utf-8';
      }
    }

    final streamed = await _client.send(request).timeout(Duration(milliseconds: timeoutMs));
    final response = await http.Response.fromStream(streamed);
    final lowerHeaders = <String, String>{};
    response.headers.forEach((k, v) => lowerHeaders[k.toLowerCase()] = v);

    var data = utf8.decode(response.bodyBytes, allowMalformed: true);
    final contentType = lowerHeaders['content-type'] ?? '';
    final looksJson = contentType.contains('json') ||
        data.trimLeft().startsWith('{') ||
        data.trimLeft().startsWith('[');
    if (looksJson && data.isNotEmpty) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        // 交给 JS 侧自己处理
      }
    }

    final ok = response.statusCode >= 200 && response.statusCode < 400;
    return <String, dynamic>{
      'ok': ok,
      'status': response.statusCode,
      'data': data,
      'headers': lowerHeaders,
      'url': response.request?.url.toString() ?? uri.toString(),
    };
  }

  Uri _buildUri(String url, dynamic params) {
    var normalized = url.trim();
    if (normalized.startsWith('//')) normalized = 'https:$normalized';
    final uri = Uri.tryParse(normalized);
    if (uri == null) throw RuntimeException('非法 URL: $url');
    if (params is Map && params.isNotEmpty) {
      final query = <String, String>{};
      params.forEach((k, v) {
        if (v != null) query[k.toString()] = v.toString();
      });
      return uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    return uri;
  }

  void dispose() {
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(RuntimeException('组件已卸载'));
    }
    _pending.clear();
    _booted = false;
  }
}
