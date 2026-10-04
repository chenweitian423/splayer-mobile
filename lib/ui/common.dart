/// 通用 UI 组件。
library;

import 'package:flutter/material.dart';

import '../models/capy_models.dart';
import 'poster_image.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, this.onTap, this.width = 120, this.referer = ''});

  final MediaItem item;
  final VoidCallback? onTap;
  final double width;

  /// 封面防盗链用的 Referer（来自组件运行时）。
  final String referer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = item.posterUrl.isNotEmpty ? item.posterUrl : item.backdropUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: image.isEmpty
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.movie_outlined, color: theme.colorScheme.outline),
                      )
                    : PosterImage(
                        url: image,
                        referer: referer,
                        placeholderColor: theme.colorScheme.surfaceContainerHighest,
                        fallback: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class HorizontalPosterRow extends StatefulWidget {
  const HorizontalPosterRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTapItem,
    this.loading = false,
    this.error = '',
    this.onRetry,
    this.onMore,
    this.onLoadMore,
    this.loadingMore = false,
    this.hasMore = false,
    this.referer = '',
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem item) onTapItem;
  final bool loading;
  final String error;
  final VoidCallback? onRetry;
  final VoidCallback? onMore;

  /// 横向滚动接近末尾时回调，用于追加下一页；为空表示该行不分页。
  final VoidCallback? onLoadMore;
  final bool loadingMore;
  final bool hasMore;

  /// 封面防盗链用的 Referer（来自组件运行时）。
  final String referer;

  @override
  State<HorizontalPosterRow> createState() => _HorizontalPosterRowState();
}

class _HorizontalPosterRowState extends State<HorizontalPosterRow> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void didUpdateWidget(HorizontalPosterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onLoadMore != null && widget.items.length > oldWidget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    final onLoadMore = widget.onLoadMore;
    if (onLoadMore == null || widget.loadingMore || !widget.hasMore) return;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // 内容不足以滚动（maxScrollExtent == 0）时也触发，避免首页首屏只有一屏却停住
    if (position.pixels >= position.maxScrollExtent - 400) {
      onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paged = widget.onLoadMore != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (widget.onMore != null)
                TextButton(onPressed: widget.onMore, child: const Text('全部')),
            ],
          ),
        ),
        if (widget.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorBanner(message: widget.error, onRetry: widget.onRetry),
          ),
        if (widget.loading)
          const SizedBox(
            height: 190,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.items.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '该分类暂无内容${widget.onMore != null ? '（点右上角「全部」换个分类）' : ''}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          )
        else
          SizedBox(
            height: 208,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.items.length + (paged ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index >= widget.items.length) {
                  return _PagingTile(
                    width: 120,
                    loading: widget.loadingMore,
                    hasMore: widget.hasMore,
                    onPressed: widget.onLoadMore,
                  );
                }
                return PosterCard(
                  item: widget.items[index],
                  referer: widget.referer,
                  onTap: () => widget.onTapItem(widget.items[index]),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// 横向列表末尾的「加载更多 / 已到底」贴片。
class _PagingTile extends StatelessWidget {
  const _PagingTile({required this.width, required this.loading, required this.hasMore, this.onPressed});

  final double width;
  final bool loading;
  final bool hasMore;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Center(
        child: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
            : InkWell(
                onTap: hasMore ? onPressed : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        hasMore ? Icons.more_horiz : Icons.check_circle_outline,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasMore ? '加载更多' : '已到底',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// 网格海报（搜索结果 / 分类全量）。
///
/// ★ [controller] 必须挂到内部的可滚动组件上 —— 曾经漏了这个参数，
/// 导致调用方 `addListener` 的「滚到底加载下一页」永远不触发（每页只有 1 页）。
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.items,
    required this.onTapItem,
    this.padding = const EdgeInsets.all(16),
    this.bottomPadding = 24,
    this.controller,
    this.footer,
    this.referer = '',
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onTapItem;
  final EdgeInsets padding;
  final double bottomPadding;
  final ScrollController? controller;

  /// 网格末尾追加的内容（加载中 / 已到底 / 错误重试）。
  final Widget? footer;

  /// 封面防盗链用的 Referer（来自组件运行时）。
  final String referer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left,
            padding.top,
            padding.right,
            footer == null ? bottomPadding : 4,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 0.55,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => PosterCard(
              item: items[index],
              width: double.infinity,
              referer: referer,
              onTap: () => onTapItem(items[index]),
            ),
          ),
        ),
        if (footer != null)
          SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.only(bottom: bottomPadding), child: footer),
          ),
      ],
    );
  }
}

/// 分页列表末尾的状态条（加载中 / 已加载全部 / 失败重试）。
class PagingFooter extends StatelessWidget {
  const PagingFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.error,
    this.count = 0,
    this.onRetry,
  });

  final bool loading;
  final bool hasMore;
  final String error;
  final int count;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (error.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(message: error, onRetry: onRetry),
      );
    }
    if (loading && count > 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    }
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          hasMore ? '上滑加载更多' : '已加载全部 $count 条',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ),
    );
  }
}
