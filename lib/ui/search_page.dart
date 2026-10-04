/// 搜索页：按组件并发搜索，结果合并去重。
library;

import 'package:flutter/material.dart';

import '../models/capy_models.dart';
import '../runtime/plugin_engine.dart';
import '../runtime/widget_runtime.dart';
import '../store/plugin_store.dart';
import 'common.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final Map<String, MediaItem> _results = <String, MediaItem>{};
  final Map<String, WidgetRuntime> _runtimeOfResult = <String, WidgetRuntime>{};
  final List<String> _errors = <String>[];
  bool _searching = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searched = true;
      _results.clear();
      _runtimeOfResult.clear();
      _errors.clear();
    });

    final records = PluginStore.instance.enabledRecords;
    await Future.wait(records.map((record) async {
      try {
        final runtime = await PluginEngine.instance.runtimeFor(record);
        final items = await runtime.search(keyword);
        if (!mounted) return;
        setState(() {
          for (final item in items) {
            final key = '${record.id}:${item.id.isEmpty ? item.title : item.id}';
            _results[key] = item;
            _runtimeOfResult[key] = runtime;
          }
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _errors.add('${record.title}: $e'));
      }
    }));

    if (!mounted) return;
    setState(() => _searching = false);
  }

  /// 搜索结果来自多个组件，取第一个拿得出 Referer 的运行时（封面防盗链用）。
  String get _imageReferer {
    for (final runtime in _runtimeOfResult.values) {
      final referer = runtime.imageReferer;
      if (referer.isNotEmpty) return referer;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '搜索影片 / 演员',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
        ),
        if (_searching) const LinearProgressIndicator(),
        if (_errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ErrorBanner(message: _errors.take(3).join('\n')),
          ),
        Expanded(
          child: !_searched
              ? const Center(child: Text('输入关键词，在所有已启用组件里搜索'))
              : _results.isEmpty && !_searching
                  ? const Center(child: Text('没有结果'))
                  : PosterGrid(
                      items: _results.values.toList(),
                      referer: _imageReferer,
                      onTapItem: (item) {
                        final key = _results.entries.firstWhere((e) => identical(e.value, item)).key;
                        final runtime = _runtimeOfResult[key];
                        if (runtime == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DetailPage(runtime: runtime, item: item),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
