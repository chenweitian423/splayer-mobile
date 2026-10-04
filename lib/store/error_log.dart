/// 全局错误日志：把未捕获的异常落盘，用户可一键复制发回来。
///
/// 为什么需要它：release 包里 Flutter 的异常是**静默吞掉**的，用户只能说
/// 「闪退」，我们拿不到堆栈。装上这个钩子后，闪退前的最后一条异常会留在
/// `<appDocs>/error.log`，设置页里能直接复制。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ErrorLog extends ChangeNotifier {
  ErrorLog._();

  static final ErrorLog instance = ErrorLog._();

  static const int maxEntries = 200;

  final List<String> _entries = <String>[];
  bool _loaded = false;

  List<String> get entries => List.unmodifiable(_entries);
  int get count => _entries.length;

  /// 装全局钩子。在 `runApp` 之前调用一次。
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previous?.call(details);
      add('框架', details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      add('未捕获', error, stack);
      return true; // 已记录，不让它直接把进程带走
    };
  }

  void add(String tag, Object error, StackTrace? stack) {
    final buffer = StringBuffer()
      ..writeln('[${DateTime.now().toIso8601String()}] [$tag] $error');
    if (stack != null) {
      buffer.writeln(stack.toString().split('\n').take(12).join('\n'));
    }
    _entries.insert(0, buffer.toString().trimRight());
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        final text = await file.readAsString();
        // 以时间戳行分段还原成多条。
        final blocks = text.split(RegExp(r'\n(?=\[\d{4}-)'));
        _entries
          ..clear()
          ..addAll(blocks.map((b) => b.trim()).where((b) => b.isNotEmpty).take(maxEntries));
      }
    } catch (e) {
      debugPrint('error.log 读取失败: $e');
    }
    notifyListeners();
  }

  Future<void> clear() async {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
    await _persist();
  }

  String asText() => _entries.isEmpty ? '（暂无错误记录）' : _entries.join('\n\n');

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/error.log');
  }

  Future<void> _persist() async {
    try {
      final file = await _file();
      await file.writeAsString(asText());
    } catch (_) {
      // 记日志本身失败就算了，别再抛。
    }
  }
}
