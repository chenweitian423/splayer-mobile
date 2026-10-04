/// 首页：按组件分组展示其第一个模块的内容。
library;

import 'package:flutter/material.dart';

import '../models/capy_models.dart';
import '../models/paging.dart';
import '../runtime/plugin_engine.dart';
import '../runtime/widget_runtime.dart';
import '../store/plugin_store.dart';
import 'common.dart';
import 'detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[PluginStore.instance, PluginEngine.instance]),
      builder: (context, _) {
        final records = PluginStore.instance.enabledRecords;
        if (records.isEmpty) {
          return const _EmptyState();
        }
        return RefreshIndicator(
          onRefresh: () async {
            // 下拉刷新 = 唯一主动清缓存的入口：清掉首屏缓存并卸载运行时，全部重新拉。
            clearHomeSectionCache();
            for (final record in records) {
              PluginEngine.instance.drop(record.id);
            }
            setState(() {});
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              for (final record in records) _PluginSection(key: ValueKey(record.id), record: record),
            ],
          ),
        );
      },
    );
  }
}

/// 首页分区的首屏缓存：key = `recordId|moduleId`。
///
/// 光靠 `AutomaticKeepAliveClientMixin` 还不够 —— 一旦分区被真正重建
/// （切标签页、增删组件等），没有缓存就会**再打一次网络**，用户看到的就是
/// 「滑回去又加载一遍」。有缓存则先秒出旧内容，只有下拉刷新才会重新请求。
final Map<String, List<MediaItem>> _homeSectionCache = <String, List<MediaItem>>{};

void clearHomeSectionCache() => _homeSectionCache.clear();

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.extension_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('还没有任何组件'),
            const SizedBox(height: 8),
            Text(
              '去「插件」页导入一个 .js 组件地址，或粘贴组件托管页批量导入',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginSection extends StatefulWidget {
  const _PluginSection({super.key, required this.record});

  final PluginRecord record;

  @override
  State<_PluginSection> createState() => _PluginSectionState();
}

class _PluginSectionState extends State<_PluginSection> with AutomaticKeepAliveClientMixin {
  WidgetRuntime? _runtime;
  CapyModule? _module;
  List<MediaItem> _items = const <MediaItem>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String _error = '';

  /// 分区被移出视口后仍保留状态 —— 否则每次滑回来都会 initState 重新拉一遍。
  @override
  bool get wantKeepAlive => true;

  String get _cacheKey => widget.record.id;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// 取运行时。失败会自动再试一次 —— 「第一次用完关掉、再打开就有组件未装载」
  /// 多半是重开时 WebView 还忙着导致的偶发失败，重试一次通常就好了。
  ///
  /// ★ 外层还套了超时：**无论引擎内部卡在哪一步，分区都不会无声转圈**，
  ///   要么出内容、要么出可点的错误（v1.0.9 那次「一直转圈还没日志」就是缺这层兜底）。
  Future<WidgetRuntime> _runtimeWithRetry() async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await PluginEngine.instance.runtimeFor(widget.record).timeout(
              const Duration(seconds: 90),
              onTimeout: () => throw Exception('装载超时（90 秒无响应）'),
            );
      } catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    throw Exception('$lastError');
  }

  Future<void> _boot() async {
    final cached = _homeSectionCache[_cacheKey];
    final hasCache = cached != null && cached.isNotEmpty;
    setState(() {
      _loading = !hasCache;
      _error = '';
      _items = hasCache ? cached : const <MediaItem>[];
      _page = hasCache ? 2 : 1;
      _hasMore = hasCache;
    });
    try {
      // runtimeFor 命中已有运行时是零成本；即使重建也只是重新注入脚本，不打网络。
      final runtime = await _runtimeWithRetry();
      final module = pickHomeModule(runtime.meta?.modules ?? const <CapyModule>[]);
      if (module == null) {
        throw RuntimeException('组件未声明任何可用模块');
      }
      if (!mounted) return;
      setState(() {
        _runtime = runtime;
        _module = module;
      });

      if (hasCache) return; // 有缓存就不重复请求首屏

      final items = await runtime
          .callList(module, overrides: <String, dynamic>{'page': 1})
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('内容加载超时（60 秒无响应）'),
          );
      if (!mounted) return;
      _homeSectionCache[_cacheKey] = items;
      setState(() {
        _items = items;
        _page = 2;
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 有缓存时保持旧内容，不把错误糊到用户脸上。
        if (!hasCache) _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 追加下一页（首页每行横向滚到底触发）。
  Future<void> _loadMore() async {
    final runtime = _runtime;
    final module = _module;
    if (runtime == null || module == null) return;
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final items = await runtime.callList(module, overrides: <String, dynamic>{'page': _page});
      if (!mounted) return;
      setState(() {
        final merged = mergePage(_items, items, _itemKey);
        _items = merged.items;
        _homeSectionCache[_cacheKey] = merged.items;
        _page += 1;
        // 满页但没有新增（后端忽略 page 或已到末尾）→ 视为到底，避免无限重复。
        _hasMore = items.isNotEmpty && merged.added > 0;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  void _open(MediaItem item) {
    final runtime = _runtime;
    if (runtime == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DetailPage(runtime: runtime, item: item, pluginTitle: widget.record.title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final title = _module == null ? widget.record.title : '${widget.record.title} · ${_module!.title}';
    return HorizontalPosterRow(
      title: title,
      items: _items,
      loading: _loading,
      error: _error,
      onRetry: _boot,
      onTapItem: _open,
      onLoadMore: _loadMore,
      loadingMore: _loadingMore,
      hasMore: _hasMore,
      referer: _runtime?.imageReferer ?? '',
      onMore: _runtime == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PluginBrowsePage(
                    record: widget.record,
                    runtime: _runtime!,
                    initialModule: _module,
                  ),
                ),
              );
            },
    );
  }
}

/// 条目的去重键：优先 id，缺失时退回标题+海报。
String _itemKey(MediaItem item) =>
    item.id.isNotEmpty ? item.id : '${item.title}@${item.posterUrl}';

/// 单个组件的全部模块（分类）浏览。
class PluginBrowsePage extends StatefulWidget {
  const PluginBrowsePage({super.key, required this.record, required this.runtime, this.initialModule});

  final PluginRecord record;
  final WidgetRuntime runtime;
  final CapyModule? initialModule;

  @override
  State<PluginBrowsePage> createState() => _PluginBrowsePageState();
}

class _PluginBrowsePageState extends State<PluginBrowsePage> {
  late final List<CapyModule> _modules = widget.runtime.meta?.modules ?? const <CapyModule>[];

  @override
  Widget build(BuildContext context) {
    if (_modules.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(widget.record.title)), body: const Center(child: Text('该组件没有可用模块')));
    }
    final home = pickHomeModule(_modules);
    final initialIndex = home == null ? 0 : _modules.indexWhere((m) => m.id == home.id);
    return DefaultTabController(
      length: _modules.length,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.record.title),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[for (final m in _modules) Tab(text: m.title)],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            for (final m in _modules) _ModuleList(runtime: widget.runtime, module: m),
          ],
        ),
      ),
    );
  }
}

class _ModuleList extends StatefulWidget {
  const _ModuleList({required this.runtime, required this.module});

  final WidgetRuntime runtime;
  final CapyModule module;

  @override
  State<_ModuleList> createState() => _ModuleListState();
}

class _ModuleListState extends State<_ModuleList> {
  final ScrollController _scroll = ScrollController();
  final List<MediaItem> _items = <MediaItem>[];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // ★ 这个监听只有把 _scroll 真正挂到滚动组件上才有效
    // （PosterGrid 曾经没有 controller 参数，导致永远只加载第 1 页）。
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// 首屏未填满一屏时继续加载，直到填满或到底。
  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0 && _hasMore && !_loading) {
        _loadMore();
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final items = await widget.runtime
          .callList(widget.module, overrides: <String, dynamic>{'page': _page})
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception('内容加载超时（60 秒无响应）'),
          );
      if (!mounted) return;
      setState(() {
        final merged = mergePage(_items, items, _itemKey);
        _items
          ..clear()
          ..addAll(merged.items);
        _page += 1;
        // 满页但零新增（后端忽略 page / 已到末尾）→ 停止，避免无限重复追加。
        _hasMore = items.isNotEmpty && merged.added > 0;
        _loading = false;
      });
      _fillViewport();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && !_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ErrorBanner(message: _error.isEmpty ? '该分类暂无内容' : _error, onRetry: _loadMore),
        ),
      );
    }
    return PosterGrid(
      controller: _scroll,
      items: _items,
      bottomPadding: 24,
      referer: widget.runtime.imageReferer,
      onTapItem: (item) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DetailPage(runtime: widget.runtime, item: item, pluginTitle: widget.module.title),
          ),
        );
      },
      footer: PagingFooter(
        loading: _loading,
        hasMore: _hasMore,
        error: _error,
        count: _items.length,
        onRetry: _loadMore,
      ),
    );
  }
}
