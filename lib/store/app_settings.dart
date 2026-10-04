/// 应用级设置（轻量、落盘）。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _kAutoPlayNext = 'autoPlayNext';
  static const String _kAutoCheckUpdate = 'autoCheckUpdate';

  bool _autoPlayNext = true;
  bool _autoCheckUpdate = true;

  /// 一集播完自动接下一集（详情页是剧集模式时才生效）。
  bool get autoPlayNext => _autoPlayNext;

  /// 启动时自动查一次更新（只提示，不自动装）。
  bool get autoCheckUpdate => _autoCheckUpdate;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoPlayNext = prefs.getBool(_kAutoPlayNext) ?? true;
      _autoCheckUpdate = prefs.getBool(_kAutoCheckUpdate) ?? true;
    } catch (e) {
      debugPrint('读取设置失败: $e');
    }
    notifyListeners();
  }

  Future<void> setAutoPlayNext(bool value) async {
    if (_autoPlayNext == value) return;
    _autoPlayNext = value;
    notifyListeners();
    await _write(_kAutoPlayNext, value);
  }

  Future<void> setAutoCheckUpdate(bool value) async {
    if (_autoCheckUpdate == value) return;
    _autoCheckUpdate = value;
    notifyListeners();
    await _write(_kAutoCheckUpdate, value);
  }

  Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('写入设置失败: $e');
    }
  }
}
