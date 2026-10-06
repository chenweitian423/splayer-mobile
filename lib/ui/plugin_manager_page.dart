/// 插件管理：导入（URL / 剪贴板 / 本地文件 / 托管页批量）、启停、删除、自检。
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../runtime/plugin_engine.dart';
import '../store/plugin_store.dart';

class PluginManagerPage extends StatefulWidget {
  const PluginManagerPage({super.key});

  @override
  State<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends State<PluginManagerPage> {
  bool _busy = false;
  String _status = '';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(String label, Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _status = label;
    });
    try {
      final result = await action();
      _toast(result);
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从网络地址导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('粘贴 js 直链，或托管页上的「安装」深链（add-widget?data=…）。', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(hintText: 'https://example.com/widgets/x.js'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final text = await Clipboard.getData(Clipboard.kTextPlain);
              controller.text = text?.text?.trim() ?? controller.text;
            },
            child: const Text('读剪贴板'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('导入')),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _run('正在下载组件…', () async {
      final record = await PluginStore.instance.importFromUrl(url);
      return '已导入：${record.title} v${record.version}';
    });
    if (mounted) setState(() {});
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _toast('剪贴板是空的');
      return;
    }
    await _run('正在导入…', () async {
      if (looksLikeWidgetUrl(text)) {
        final record = await PluginStore.instance.importFromUrl(text);
        return '已导入：${record.title}';
      }
      final record = await PluginStore.instance.importSource(text, sourceUrl: 'clipboard');
      return '已导入：${record.title}';
    });
    if (mounted) setState(() {});
  }

  Future<void> _importFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['js'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    final content = file.bytes != null ? utf8.decode(file.bytes!, allowMalformed: true) : '';
    if (content.isEmpty) {
      _toast('文件读取失败（为空）');
      return;
    }
    await _run('正在导入…', () async {
      final record = await PluginStore.instance.importSource(content, sourceUrl: file.name);
      return '已导入：${record.title}';
    });
    if (mounted) setState(() {});
  }

  Future<void> _importFromHostPage() async {
    final controller = TextEditingController();
    final pageUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从组件托管页批量导入'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '粘贴托管页地址，会自动列出页面上出现的全部 .js 并逐个校验；'
              '页面里只写文件名（真实地址在 /widgets/ 下）的托管页也能识别。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'https://host.example.com/'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('扫描')),
        ],
      ),
    );
    if (pageUrl == null || pageUrl.isEmpty) return;

    setState(() {
      _busy = true;
      _status = '正在扫描托管页…';
    });
    List<HostPageCandidate> candidates = <HostPageCandidate>[];
    try {
      candidates = await PluginStore.instance.scanHostPage(pageUrl);
    } catch (e) {
      _toast(e.toString());
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    if (candidates.isEmpty) {
      _toast('页面里没有可导入的 .js');
      return;
    }
    final valid = candidates.where((c) => c.valid).toList();
    final selected = await showModalBottomSheet<List<HostPageCandidate>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CandidateSheet(candidates: candidates),
    );
    if (selected == null || selected.isEmpty) return;
    await _run('正在导入 ${selected.length} 个组件…', () async {
      var ok = 0;
      final failed = <String>[];
      for (final candidate in selected) {
        try {
          await PluginStore.instance.importFromUrl(candidate.url);
          ok += 1;
        } catch (e) {
          failed.add('${candidate.url.split('/').last}: $e');
        }
      }
      return failed.isEmpty ? '成功导入 $ok 个组件' : '成功 $ok 个，失败 ${failed.length} 个';
    });
    if (mounted) setState(() {});
    if (valid.isEmpty) _toast('没有校验通过的组件');
  }

  Future<void> _diagnose(PluginRecord record) async {
    setState(() {
      _busy = true;
      _status = '正在自检 ${record.title}…';
    });
    try {
      final runtime = await PluginEngine.instance.runtimeFor(record);
      final report = await runtime.diagnose();
      final meta = runtime.meta;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('自检：${record.title}'),
          content: SingleChildScrollView(
            child: Text(
              const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
                'version': meta?.version,
                'modules': meta?.modules.map((m) => m.title).toList(),
                'globalParams': meta?.globalParams.map((p) => p.name).toList(),
                'search': meta?.searchFunctionName,
                'runtime': report,
              }),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      );
    } catch (e) {
      _toast('自检失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[PluginStore.instance, PluginEngine.instance]),
      builder: (context, _) {
        final records = PluginStore.instance.records;
        return Scaffold(
          appBar: AppBar(
            title: const Text('插件'),
            bottom: _busy
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(28),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text(_status, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  )
                : null,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : () => _showImportSheet(),
            icon: const Icon(Icons.add),
            label: const Text('导入'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: <Widget>[
              if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('还没有组件，点右下角导入')),
                ),
              for (final record in records)
                _PluginTile(
                  record: record,
                  onDiagnose: () => _diagnose(record),
                  onToggle: (value) async {
                    await PluginStore.instance.setEnabled(record, value);
                    if (!value) PluginEngine.instance.drop(record.id);
                    if (mounted) setState(() {});
                  },
                  onDelete: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('删除 ${record.title}？'),
                        content: const Text('只会删掉本地快照，不影响远端的 .js 文件。'),
                        actions: <Widget>[
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    PluginEngine.instance.drop(record.id);
                    await PluginStore.instance.remove(record);
                    if (mounted) setState(() {});
                  },
                  onUpdate: () async {
                    if (record.sourceUrl.isEmpty || !record.sourceUrl.startsWith('http')) {
                      _toast('该组件不是从网络地址导入的，无法在线更新');
                      return;
                    }
                    await _run('正在更新…', () async {
                      final updated = await PluginStore.instance.importFromUrl(record.sourceUrl);
                      PluginEngine.instance.drop(updated.id);
                      return '已更新：${updated.title} v${updated.version}';
                    });
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showImportSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('从网络地址导入'),
              subtitle: const Text('粘贴 js 直链'),
              onTap: () {
                Navigator.pop(context);
                _importFromUrl();
              },
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('从组件托管页批量导入'),
              subtitle: const Text('自动列出页面里全部 .js 并校验'),
              onTap: () {
                Navigator.pop(context);
                _importFromHostPage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('从剪贴板粘贴'),
              subtitle: const Text('支持直链、安装深链或整段 js 源码'),
              onTap: () {
                Navigator.pop(context);
                _importFromClipboard();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('从本地文件导入'),
              onTap: () {
                Navigator.pop(context);
                _importFromFile();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginTile extends StatelessWidget {
  const _PluginTile({
    required this.record,
    required this.onToggle,
    required this.onDelete,
    required this.onUpdate,
    required this.onDiagnose,
  });

  final PluginRecord record;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onUpdate;
  final VoidCallback onDiagnose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final engine = PluginEngine.instance;
    final error = engine.errorOf(record.id);
    final ready = engine.isReady(record.id);
    final lines = <String>['v${record.version}'];
    if (record.sourceUrl.isNotEmpty) lines.add(record.sourceUrl);
    if (error.isNotEmpty) lines.add('错误：$error');
    return ListTile(
      leading: Icon(
        ready ? Icons.check_circle_outline : Icons.extension_outlined,
        color: error.isNotEmpty ? theme.colorScheme.error : null,
      ),
      title: Text(record.title),
      subtitle: Text(
        lines.join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: error.isNotEmpty ? theme.colorScheme.error : theme.colorScheme.outline,
        ),
      ),
      isThreeLine: lines.length > 1,
      onTap: onDiagnose,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Switch(value: record.enabled, onChanged: onToggle),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'diagnose':
                  onDiagnose();
                  break;
                case 'update':
                  onUpdate();
                  break;
                case 'source':
                  if (record.sourceUrl.isNotEmpty) {
                    launchUrl(Uri.parse(record.sourceUrl));
                  }
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'diagnose', child: Text('运行时自检')),
              const PopupMenuItem<String>(value: 'update', child: Text('从原地址更新')),
              if (record.sourceUrl.isNotEmpty)
                const PopupMenuItem<String>(value: 'source', child: Text('打开源地址')),
              const PopupMenuItem<String>(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}

/// 托管页扫描结果选择面板。
class _CandidateSheet extends StatefulWidget {
  const _CandidateSheet({required this.candidates});

  final List<HostPageCandidate> candidates;

  @override
  State<_CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<_CandidateSheet> {
  late final Set<String> _selected = widget.candidates.where((c) => c.valid).map((c) => c.url).toSet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validCount = widget.candidates.where((c) => c.valid).length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '扫描到 ${widget.candidates.length} 个 .js，其中 $validCount 个是组件',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _selected
                        ..clear()
                        ..addAll(widget.candidates.where((c) => c.valid).map((c) => c.url));
                    }),
                    child: const Text('只选有效'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: widget.candidates.length,
                itemBuilder: (context, index) {
                  final candidate = widget.candidates[index];
                  final checked = _selected.contains(candidate.url);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: candidate.valid
                        ? (value) => setState(() {
                              if (value == true) {
                                _selected.add(candidate.url);
                              } else {
                                _selected.remove(candidate.url);
                              }
                            })
                        : null,
                    title: Text(
                      candidate.title.isNotEmpty ? candidate.title : candidate.url.split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      candidate.valid ? candidate.url : '${candidate.url}\n${candidate.error}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                    secondary: Icon(
                      candidate.valid ? Icons.verified_outlined : Icons.help_outline,
                      color: candidate.valid ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text('已选 ${_selected.length} 个', style: theme.textTheme.bodySmall)),
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(
                              context,
                              widget.candidates.where((c) => _selected.contains(c.url)).toList(),
                            ),
                    child: const Text('导入所选'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
