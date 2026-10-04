/// 应用级设置（轻量、落盘）。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _kAutoPlayNext = 'autoPlayNext';

  bool _autoPlayNext = true;

  /// 一集播完自动接下一集（详情页是剧集模式时才生效）。
  bool get autoPlayNext => _autoPlayNext;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoPlayNext = prefs.getBool(_kAutoPlayNext) ?? true;
    } catch (e) {
      debugPrint('读取设置失败: $e');
    }
    notifyListeners();
  }

  Future<void> setAutoPlayNext(bool value) async {
    if (_autoPlayNext == value) return;
    _autoPlayNext = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoPlayNext, value);
    } catch (e) {
      debugPrint('写入设置失败: $e');
    }
  }
}
