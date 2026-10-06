/// 应用级设置（轻量、落盘）。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _kAutoPlayNext = 'autoPlayNext';
  static const String _kAutoCheckUpdate = 'autoCheckUpdate';
  static const String _kTmdbProxyBase = 'tmdbProxyBase';
  static const String _kHlsRelay = 'hlsRelay';

  bool _autoPlayNext = true;
  bool _autoCheckUpdate = true;
  String _tmdbProxyBase = '';
  bool _hlsRelay = false;

  /// 一集播完自动接下一集（详情页是剧集模式时才生效）。
  bool get autoPlayNext => _autoPlayNext;

  /// 启动时自动查一次更新（只提示，不自动装）。
  bool get autoCheckUpdate => _autoCheckUpdate;

  /// TMDB 中转地址（形如 `http://192.168.123.80:8788/ext/tmdb`）。
  ///
  /// 组件里的 `Widget.tmdb.get(path, opts)` 会被打到这个地址，由中转侧带
  /// TMDB API Key（并走转发机自己的网络）去请求 —— 解决「客户端连不上
  /// api.themoviedb.org」的问题。留空时尝试从组件来源地址自动推导。
  String get tmdbProxyBase => _tmdbProxyBase;

  /// 播放兼容中转（应用内 HLS 中转），**默认关闭**。
  ///
  /// 打开后，HLS 的分片与密钥改由 App 自己去拉（超时 60s + 失败重试），
  /// 播放器只面对本机 localhost —— 解决「上游 CDN 连接慢导致
  /// Android 报 Source error、iOS 却能播」的问题。
  bool get hlsRelay => _hlsRelay;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoPlayNext = prefs.getBool(_kAutoPlayNext) ?? true;
      _autoCheckUpdate = prefs.getBool(_kAutoCheckUpdate) ?? true;
      _tmdbProxyBase = (prefs.getString(_kTmdbProxyBase) ?? '').trim();
      _hlsRelay = prefs.getBool(_kHlsRelay) ?? false;
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

  /// 设置 TMDB 中转地址（传空串 = 恢复自动推导）。
  Future<void> setTmdbProxyBase(String value) async {
    final next = value.trim();
    if (_tmdbProxyBase == next) return;
    _tmdbProxyBase = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTmdbProxyBase, next);
    } catch (e) {
      debugPrint('写入设置失败: $e');
    }
  }

  Future<void> setHlsRelay(bool value) async {
    if (_hlsRelay == value) return;
    _hlsRelay = value;
    notifyListeners();
    await _write(_kHlsRelay, value);
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
