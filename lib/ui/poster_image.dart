/// 封面图加载：带浏览器 UA / Referer，失败自动换一套请求头重试。
///
/// 背景（真机现象）：MissAV 的封面绝大多数加载不出来（8 支组件里它最明显），
/// 只有一两张能出。原因是封面 CDN（`fourhoi.com` / `spic2-*.71352.men` 等）
/// 会挡「非浏览器 UA / 无 Referer」的直连；而 `CachedNetworkImage` 默认发的是
/// Dart 的 UA，也不带 Referer。
///
/// 组件自己取封面时用的是 `MISSAV_UA`（iPhone UA）+ `Accept: image/*`，
/// 说明这些 CDN 认浏览器 UA —— 宿主侧把同样的请求头补上即可。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 图片请求用的浏览器 UA（对齐组件里 MISSAV_UA 的形态）。
const String kImageUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Mobile/15E148 Safari/604.1';

/// 组装图片请求头。
///
/// [withReferer] 为真时补一个 Referer：优先用 [referer]
/// （组件自己请求站点时用的那个，由 `WidgetRuntime.imageReferer` 采集），
/// 没有则退化为图片 URL 的**同源**地址（浏览器直接打开图片时就是这个形态）。
Map<String, String> imageHeaders(String url, {bool withReferer = false, String referer = ''}) {
  final headers = <String, String>{
    'User-Agent': kImageUserAgent,
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };
  if (withReferer) {
    final trimmed = referer.trim();
    final origin = _originOf(url);
    final resolved = trimmed.isNotEmpty ? trimmed : (origin.isEmpty ? '' : '$origin/');
    if (resolved.isNotEmpty) headers['Referer'] = resolved;
  }
  return headers;
}

String _originOf(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return '';
  return '${uri.scheme}://${uri.host}';
}

/// 封面图：先按「浏览器头」请求，失败再带同源 Referer 重试一次。
class PosterImage extends StatefulWidget {
  const PosterImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback,
    this.placeholderColor,
    this.referer = '',
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// 全部尝试失败（或 URL 为空）时显示的占位内容。
  final Widget? fallback;
  final Color? placeholderColor;

  /// 重试时使用的 Referer（来自组件自己请求站点时用的那个）。
  final String referer;

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  static const int _maxAttempts = 2;
  int _attempt = 0;

  @override
  void didUpdateWidget(PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _attempt = 0;
  }

  Widget _box({Widget? child}) => Container(
        width: widget.width,
        height: widget.height,
        color: widget.placeholderColor ?? const Color(0x22888888),
        child: child,
      );

  void _retryOnce() {
    if (_attempt + 1 >= _maxAttempts) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _attempt += 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.url.trim();
    if (url.isEmpty) return widget.fallback ?? _box();

    return CachedNetworkImage(
      imageUrl: url,
      // 换头重试要换 cacheKey，否则会命中失败缓存、永远不再发请求。
      cacheKey: _attempt == 0 ? url : '$url#retry$_attempt',
      httpHeaders: imageHeaders(url, withReferer: _attempt > 0, referer: widget.referer),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: const Duration(milliseconds: 160),
      placeholder: (_, __) => _box(),
      errorWidget: (_, __, ___) {
        _retryOnce();
        return widget.fallback ?? _box();
      },
    );
  }
}
