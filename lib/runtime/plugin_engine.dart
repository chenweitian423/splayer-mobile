/// 组件引擎：负责装载/复用运行实例，并把所有 WebView 挂到界面树上。
///
/// WebView 必须有尺寸（哪怕很小）才会稳定跑 JS，所以这里把宿主放在屏幕外
/// 而不是用 Offstage（Offstage 会让 WebView 被 suspend，定时器/回调失灵）。
library;

import 'package:flutter/widgets.dart';

import '../store/plugin_store.dart';
import 'widget_runtime.dart';

class PluginEngine extends ChangeNotifier {
  PluginEngine._();

  static final PluginEngine instance = PluginEngine._();

  final Map<String, WidgetRuntime> _runtimes = <String, WidgetRuntime>{};
  final Map<String, Future<WidgetRuntime>> _booting = <String, Future<WidgetRuntime>>{};
  final Map<String, String> _errors = <String, String>{};

  String errorOf(String pluginId) => _errors[pluginId] ?? '';

  bool isReady(String pluginId) => _runtimes[pluginId]?.isBooted == true;

  WidgetRuntime? runtimeIfReady(String pluginId) => _runtimes[pluginId];

  Future<WidgetRuntime> runtimeFor(PluginRecord record) {
    final existing = _runtimes[record.id];
    if (existing != null && existing.isBooted) return Future<WidgetRuntime>.value(existing);

    final inflight = _booting[record.id];
    if (inflight != null) return inflight;

    final runtime = WidgetRuntime(record);
    _runtimes[record.id] = runtime;
    final future = runtime.boot().then((_) {
      _errors.remove(record.id);
      notifyListeners();
      return runtime;
    }).catchError((Object error) {
      _errors[record.id] = error.toString();
      notifyListeners();
      throw error;
    }).whenComplete(() {
      _booting.remove(record.id);
    });
    _booting[record.id] = future;
    notifyListeners();
    return future;
  }

  void drop(String pluginId) {
    _runtimes.remove(pluginId)?.dispose();
    _errors.remove(pluginId);
    notifyListeners();
  }

  /// 汇总所有组件的网络请求日志（按时间排序），用于远程排障。
  List<NetLogEntry> allNetLogs() {
    final logs = <NetLogEntry>[];
    for (final runtime in _runtimes.values) {
      logs.addAll(runtime.netLogs);
    }
    logs.sort((a, b) => b.at.compareTo(a.at));
    return logs;
  }

  void clearNetLogs() {
    for (final runtime in _runtimes.values) {
      runtime.clearNetLogs();
    }
    notifyListeners();
  }

  /// 屏幕外的 WebView 宿主，挂在 App 根部。
  Widget buildHost() {
    final ids = _runtimes.keys.toList();
    return Stack(
      children: <Widget>[
        for (var i = 0; i < ids.length; i++)
          Positioned(
            left: -1200.0 - (i * 300),
            top: -1200 - (i * 300),
            child: _RuntimeSlot(runtime: _runtimes[ids[i]]!),
          ),
      ],
    );
  }
}

class _RuntimeSlot extends StatelessWidget {
  const _RuntimeSlot({required this.runtime});

  final WidgetRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 280, height: 280, child: runtime.buildView(size: 280));
  }
}
