/// 应用内 HLS 中转。
///
/// 为什么需要它（真机 + 实测结论）：
///   * 后端只代理**清单**，清单里的**分片(.ts)与 AES 密钥**直指第三方 CDN，
///     由播放器自己去拉；
///   * 这些 CDN 主机是**轮换**的，质量差异极大 —— 实测同一时刻
///     `pic.wlwvch.cn` 连接 0.08s，而 `tx.doudou520.online` **连接要 10s**；
///   * ExoPlayer（Android）连接超时后直接报 `ExoPlaybackException: Source error`，
///     而 AVPlayer（iOS）更有耐心 —— 这正是「同一部片 iOS 能播、Android 播不了」。
///
/// 做法：在本机 `127.0.0.1` 起一个小 HTTP 服务，把清单里的分片/密钥地址改写成
/// 走本机；由 **App 自己**去拉上游（超时给到 60s、失败重试），再把字节喂给播放器。
/// 播放器面对的是 localhost，连接是瞬时的，不再因上游慢而放弃。
///
/// 注意：这只是**增加耐心与重试**，不能凭空让手机连上连不上的主机 ——
/// 若某 CDN 对手机完全不可达，仍然播不了（那种情况只能靠外部中转机）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ui/poster_image.dart' show kImageUserAgent;

/// 把清单里的相对/绝对 URI 交给 `wrap` 处理，返回改写后的清单。
///
/// 纯函数，便于单测。处理三类：
///   * 普通行（分片地址）→ 相对路径按清单地址解析成绝对地址后 wrap；
///   * `#EXT-X-KEY` / `#EXT-X-MAP` / `#EXT-X-MEDIA` 等带 `URI="…"` 的标签；
///   * 其它 `#` 行原样保留。
String rewriteHlsManifest(
  String manifest,
  String manifestUrl,
  String Function(String absoluteUrl) wrap,
) {
  final base = Uri.tryParse(manifestUrl);
  final out = <String>[];
  for (final raw in const LineSplitter().convert(manifest)) {
    final line = raw.trim();
    if (line.isEmpty) {
      out.add(raw);
      continue;
    }
    if (line.startsWith('#')) {
      out.add(
        line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
          final resolved = _resolve(base, match.group(1)!);
          return 'URI="${wrap(resolved)}"';
        }),
      );
    } else {
      out.add(wrap(_resolve(base, line)));
    }
  }
  return out.join('\n');
}

String _resolve(Uri? base, String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  if (uri.hasScheme) return uri.toString();
  if (base == null) return value;
  return base.resolveUri(uri).toString();
}

String _b64(String value) => base64Url.encode(utf8.encode(value)).replaceAll('=', '');
String _unb64(String value) {
  final padded = value + '=' * ((4 - value.length % 4) % 4);
  return utf8.decode(base64Url.decode(padded));
}

class HlsRelay {
  HlsRelay._();

  static final HlsRelay instance = HlsRelay._();

  /// 上游请求的超时。**故意给得很宽** —— 就是为了比播放器更耐心。
  static const Duration upstreamTimeout = Duration(seconds: 60);

  HttpServer? _server;

  bool get running => _server != null;
  int get port => _server?.port ?? 0;

  Future<int> ensureStarted() async {
    final existing = _server;
    if (existing != null) return existing.port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: false);
    _server = server;
    server.listen(_onRequest, onError: (Object e) => debugPrint('[relay] $e'));
    debugPrint('[relay] 已启动 http://127.0.0.1:${server.port}');
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// 把一个上游 HLS 地址包成走本机中转的地址。
  String wrap(String upstreamUrl, {String referer = ''}) {
    if (!running) return upstreamUrl;
    final u = _b64(upstreamUrl);
    final r = referer.trim().isEmpty ? '' : '&r=${_b64(referer.trim())}';
    return 'http://127.0.0.1:$port/m?u=$u$r';
  }

  /// 判断这个地址是不是要走中转的 HLS。
  ///
  /// 后端播放代理的 `/media` 虽然没扩展名，但实测下发的是 HLS 清单，一并纳入。
  static bool looksLikeHls(String url) {
    final path = Uri.tryParse(url.trim())?.path.toLowerCase() ?? '';
    if (path.endsWith('.m3u8')) return true;
    return url.contains('/api/v1/playback/') && path.endsWith('/media');
  }

  Future<void> _onRequest(HttpRequest request) async {
    final path = request.uri.path;
    final encoded = request.uri.queryParameters['u'] ?? '';
    final referer = request.uri.queryParameters['r'] ?? '';
    if (encoded.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final target = _unb64(encoded);
    final ref = referer.isEmpty ? '' : _unb64(referer);
    try {
      if (path == '/m') {
        await _serveManifest(request, target, ref);
      } else if (path == '/s') {
        await _serveBinary(request, target, ref);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e) {
      debugPrint('[relay] ${request.uri.path} 失败：$e');
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  Map<String, String> _headers(String referer) => <String, String>{
        'User-Agent': kImageUserAgent,
        'Accept': '*/*',
        if (referer.isNotEmpty) 'Referer': referer,
      };

  /// 清单：拉下来 → 改写分片/密钥地址 → 返回。
  Future<void> _serveManifest(HttpRequest request, String target, String referer) async {
    final response = await http
        .get(Uri.parse(target), headers: _headers(referer))
        .timeout(upstreamTimeout);
    if (response.statusCode != 200) {
      request.response.statusCode = response.statusCode;
      await request.response.close();
      return;
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final rewritten = rewriteHlsManifest(
      text,
      target,
      // 分片/密钥都走 /s，并把 Referer 带上（部分 CDN 校验来源）。
      (absolute) => 'http://127.0.0.1:$port/s?u=${_b64(absolute)}'
          '${referer.isEmpty ? '' : '&r=${_b64(referer)}'}',
    );
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8')
      ..add(utf8.encode(rewritten));
    await request.response.close();
  }

  /// 分片 / 密钥：App 拉上游再原样透传。失败重试一次（上游 CDN 抖动很常见）。
  Future<void> _serveBinary(HttpRequest request, String target, String referer) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final client = http.Client();
        try {
          final upstream = await client
              .send(http.Request('GET', Uri.parse(target))..headers.addAll(_headers(referer)))
              .timeout(upstreamTimeout);
          if (upstream.statusCode != 200) {
            lastError = 'HTTP ${upstream.statusCode}';
            continue;
          }
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.binary;
          if (upstream.contentLength != null) {
            request.response.headers.contentLength = upstream.contentLength!;
          }
          await request.response.addStream(upstream.stream);
          await request.response.close();
          return;
        } finally {
          client.close();
        }
      } catch (e) {
        lastError = e;
        if (attempt == 1) rethrow;
      }
    }
    throw Exception('$lastError');
  }
}
