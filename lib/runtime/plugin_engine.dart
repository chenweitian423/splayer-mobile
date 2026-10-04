/// 组件引擎：负责装载/复用运行实例，并把所有 WebView 挂到界面树上。
///
/// WebView 必须有尺寸（哪怕很小）才会稳定跑 JS，所以这里把宿主放在屏幕外
/// 而不是用 Offstage（Offstage 会让 WebView 被 suspend，定时器/回调失灵）。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../store/error_log.dart';
import '../store/plugin_store.dart';
import 'boot_gate.dart';
import 'widget_runtime.dart';

class PluginEngine extends ChangeNotifier {
  PluginEngine._();

  static final PluginEngine instance = PluginEngine._();

  /// 同时启动的 WebView 上限（低端机一起启动容易超时/被系统回收）。
  static const int maxConcurrentBoots = 3;

  /// 单次装载的整体兜底。
  ///
  /// ★ 这个看门狗是**必需**的：`WebView` 的某些调用（挂载前的 `loadHtmlString`）
  /// 可能**永远不返回**，没有它就会既不成功也不失败 —— 首页一直转圈、还没日志。
  static const Duration bootWatchdog = Duration(seconds: 75);

  final Map<String, WidgetRuntime> _runtimes = <String, WidgetRuntime>{};
  final Map<String, Future<WidgetRuntime>> _booting = <String, Future<WidgetRuntime>>{};
  final Map<String, String> _errors = <String, String>{};

  final BootGate _bootGate = BootGate(maxConcurrentBoots);
  String errorOf(String pluginId) => _errors[pluginId] ?? '';

  bool isReady(String pluginId) => _runtimes[pluginId]?.isBooted == true;

  /// 只在**确实装载好**的时候返回实例（旧实现名字叫 ready 却没检查）。
  WidgetRuntime? runtimeIfReady(String pluginId) {
    final runtime = _runtimes[pluginId];
    return (runtime != null && runtime.isBooted) ? runtime : null;
  }

  Future<WidgetRuntime> runtimeFor(PluginRecord record) {
    final existing = _runtimes[record.id];
    if (existing != null && existing.isBooted) return Future<WidgetRuntime>.value(existing);

    final inflight = _booting[record.id];
    if (inflight != null) return inflight;

    // 上一次启动失败留下的实例：先摘掉并释放，否则每次重试都会多留一个 WebView。
    if (existing != null) {
      _runtimes.remove(record.id);
      existing.dispose();
    }

    final runtime = WidgetRuntime(record);
    _runtimes[record.id] = runtime;
    final future = _bootQueued(runtime)
        .then((WidgetRuntime value) {
          _errors.remove(record.id);
          notifyListeners();
          return value;
        })
        .catchError((Object error) {
          _errors[record.id] = error.toString();
          // 也写进错误日志：组件装载失败是用户最容易遇到、又最难描述的问题。
          ErrorLog.instance.add('装载', '${record.title}：$error', null);
          // 失败的实例立刻从池子里摘掉并释放，避免它一直挂在界面树上。
          if (identical(_runtimes[record.id], runtime)) {
            _runtimes.remove(record.id);
            runtime.dispose();
          }
          notifyListeners();
          throw error;
        })
        .whenComplete(() => _booting.remove(record.id));
    _booting[record.id] = future;
    notifyListeners();
    return future;
  }

  /// 排队启动：名额由 [BootGate] 管理（直接交接给队首，不轮询）。
  Future<WidgetRuntime> _bootQueued(WidgetRuntime runtime) async {
    await _bootGate.acquire();
    try {
      await runtime.boot().timeout(
        bootWatchdog,
        onTimeout: () => throw RuntimeException(
          '组件「${runtime.record.title}」装载超时（卡在：${runtime.stage}）',
        ),
      );
      return runtime;
    } finally {
      _bootGate.release();
    }
  }

  /// 卸载一个组件；若它正在启动，启动完成后也会被丢弃。
  void drop(String pluginId) {
    _runtimes.remove(pluginId)?.dispose();
    _errors.remove(pluginId);
    notifyListeners();
  }

  /// 重新装载（先卸载再排队）。
  Future<WidgetRuntime> reload(PluginRecord record) {
    drop(record.id);
    return runtimeFor(record);
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
