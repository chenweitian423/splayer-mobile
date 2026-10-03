/// 首页：按组件分组展示其第一个模块的内容。
library;

import 'package:flutter/material.dart';

import '../models/capy_models.dart';
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

class _PluginSectionState extends State<_PluginSection> {
  WidgetRuntime? _runtime;
  CapyModule? _module;
  List<MediaItem> _items = const <MediaItem>[];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final runtime = await PluginEngine.instance.runtimeFor(widget.record);
      final module = runtime.meta?.modules.isNotEmpty == true ? runtime.meta!.modules.first : null;
      if (module == null) {
        throw RuntimeException('组件未声明模块');
      }
      final items = await runtime.callList(module);
      if (!mounted) return;
      setState(() {
        _runtime = runtime;
        _module = module;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
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
    final title = _module == null ? widget.record.title : '${widget.record.title} · ${_module!.title}';
    return HorizontalPosterRow(
      title: title,
      items: _items,
      loading: _loading,
      error: _error,
      onRetry: _boot,
      onTapItem: _open,
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
    final initialIndex = widget.initialModule == null ? 0 : _modules.indexWhere((m) => m.id == widget.initialModule!.id);
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
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400 && !_loading && _hasMore) {
        _loadMore();
      }
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final items = await widget.runtime.callList(widget.module, overrides: <String, dynamic>{'page': _page});
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _page += 1;
        _hasMore = items.isNotEmpty;
        _loading = false;
      });
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
    return Stack(
      children: <Widget>[
        PosterGrid(
          items: _items,
          bottomPadding: 96,
          onTapItem: (item) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DetailPage(runtime: widget.runtime, item: item, pluginTitle: widget.module.title),
              ),
            );
          },
        ),
        if (_items.isEmpty && _loading) const Center(child: CircularProgressIndicator()),
        if (_items.isEmpty && !_loading && _error.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ErrorBanner(message: _error, onRetry: _loadMore),
            ),
          ),
        if (_items.isNotEmpty && _loading)
          const Positioned(bottom: 16, left: 0, right: 0, child: Center(child: CircularProgressIndicator())),
        if (_error.isNotEmpty && _items.isNotEmpty)
          Positioned(left: 16, right: 16, bottom: 16, child: ErrorBanner(message: _error, onRetry: _loadMore)),
      ],
    );
  }
}
