/// 通用 UI 组件。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/capy_models.dart';

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.item, this.onTap, this.width = 120});

  final MediaItem item;
  final VoidCallback? onTap;
  final double width;

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
                    : CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(
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

class HorizontalPosterRow extends StatelessWidget {
  const HorizontalPosterRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTapItem,
    this.loading = false,
    this.error = '',
    this.onRetry,
    this.onMore,
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem item) onTapItem;
  final bool loading;
  final String error;
  final VoidCallback? onRetry;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (onMore != null)
                TextButton(onPressed: onMore, child: const Text('全部')),
            ],
          ),
        ),
        if (error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: ErrorBanner(message: error, onRetry: onRetry)),
        if (loading)
          const SizedBox(
            height: 190,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (items.isEmpty)
          Container(
            height: 120,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '该分类暂无内容${onMore != null ? '（点右上角「全部」换个分类）' : ''}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          )
        else
          SizedBox(
            height: 208,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => PosterCard(
                item: items[index],
                onTap: () => onTapItem(items[index]),
              ),
            ),
          ),
      ],
    );
  }
}

/// 网格海报（搜索结果 / 分类全量）。
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.items,
    required this.onTapItem,
    this.padding = const EdgeInsets.all(16),
    this.bottomPadding = 24,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onTapItem;
  final EdgeInsets padding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, bottomPadding),
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
        onTap: () => onTapItem(items[index]),
      ),
    );
  }
}
