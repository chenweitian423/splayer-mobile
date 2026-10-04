/// Android 在线更新：查 GitHub Release → 下载 APK → 调起系统安装器。
///
/// ★ 签名前提：新包必须与**已安装的那个包用同一把签名钥匙**，否则系统会
/// 直接拒绝安装（报「应用未安装 / 签名不一致」）。所以仓库里配了 4 个
/// GitHub Secrets（ANDROID_KEYSTORE_BASE64 / KEY_ALIAS / KEY_PASSWORD /
/// STORE_PASSWORD），CI 每次出包都用同一把 release key 签。
///
/// ★ 下载通道：优先走 **api.github.com 的资产接口**
/// （`/releases/assets/{id}` + `Accept: application/octet-stream`）。
/// 实测本机对 `github.com` 主站时通时断，而 `api.github.com` 一直可达 ——
/// 走浏览器下载地址（browser_download_url）会经常失败。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const String kUpdateOwner = 'chenweitian423';
const String kUpdateRepo = 'splayer-mobile';

/// 把 `v1.2.3` / `1.2.3+4` 解析成可比较的数字数组。
List<int> parseVersion(String raw) {
  final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final core = cleaned.split('+').first.split('-').first;
  return core
      .split('.')
      .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}

/// `a` 是否比 `b` 新。
bool isNewerVersion(String a, String b) {
  final x = parseVersion(a);
  final y = parseVersion(b);
  final len = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < len; i++) {
    final left = i < x.length ? x[i] : 0;
    final right = i < y.length ? y[i] : 0;
    if (left != right) return left > right;
  }
  return false;
}

class ApkAsset {
  const ApkAsset({
    required this.name,
    required this.browserUrl,
    required this.apiUrl,
    required this.size,
    this.sha256 = '',
  });

  final String name;
  final String browserUrl;

  /// `api.github.com/repos/.../releases/assets/<id>`（更稳的通道）。
  final String apiUrl;
  final int size;
  final String sha256;
}

class UpdateInfo {
  const UpdateInfo({required this.latestVersion, required this.notes, required this.apk});

  final String latestVersion;
  final String notes;
  final ApkAsset apk;
}

class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  static const Map<String, String> _apiHeaders = <String, String>{
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'SPlayerMobile',
  };

  String _currentVersion = '';

  /// 当前安装版本（`package_info_plus`）。
  Future<String> currentVersion() async {
    if (_currentVersion.isNotEmpty) return _currentVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (e) {
      debugPrint('读取版本失败: $e');
    }
    return _currentVersion;
  }

  /// 查最新 Release；没有可更新的安卓包时返回 null。
  Future<UpdateInfo?> check() async {
    final response = await http
        .get(Uri.parse('https://api.github.com/repos/$kUpdateOwner/$kUpdateRepo/releases/latest'),
            headers: _apiHeaders)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('查询失败：HTTP ${response.statusCode}');
    }
    final data = _decode(response.bodyBytes);
    final tag = (data['tag_name'] ?? '').toString();
    if (tag.isEmpty) return null;

    final current = await currentVersion();
    if (current.isNotEmpty && !isNewerVersion(tag, current)) return null;

    ApkAsset? asset;
    final assets = data['assets'];
    if (assets is List) {
      for (final raw in assets) {
        if (raw is! Map) continue;
        final name = (raw['name'] ?? '').toString();
        if (!name.toLowerCase().endsWith('.apk')) continue;
        final id = raw['id'];
        asset = ApkAsset(
          name: name,
          browserUrl: (raw['browser_download_url'] ?? '').toString(),
          apiUrl: id == null ? '' : 'https://api.github.com/repos/$kUpdateOwner/$kUpdateRepo/releases/assets/$id',
          size: (raw['size'] as num?)?.toInt() ?? 0,
          sha256: (raw['digest'] ?? '').toString().replaceFirst('sha256:', ''),
        );
        break;
      }
    }
    if (asset == null) return null;

    return UpdateInfo(
      latestVersion: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      notes: (data['body'] ?? '').toString(),
      apk: asset,
    );
  }

  /// 下载 APK 到应用缓存目录，[onProgress] 回调 0~1（总大小未知时为 null）。
  Future<File> download(ApkAsset asset, {void Function(double? progress)? onProgress}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${asset.name}');
    if (await file.exists()) await file.delete();

    // 先 API 通道，失败再退回浏览器下载地址。
    final urls = <String>[
      if (asset.apiUrl.isNotEmpty) asset.apiUrl,
      if (asset.browserUrl.isNotEmpty) asset.browserUrl,
    ];
    Object? lastError;
    for (final url in urls) {
      try {
        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll(<String, String>{
          'User-Agent': 'SPlayerMobile',
          if (url.contains('api.github.com')) 'Accept': 'application/octet-stream',
        });
        final response = await http.Client().send(request).timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        final total = response.contentLength ?? (asset.size > 0 ? asset.size : null);
        final sink = file.openWrite();
        var received = 0;
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null) {
            onProgress(total == null || total <= 0 ? null : received / total);
          }
        }
        await sink.close();
        if (asset.size > 0 && received < asset.size) {
          throw Exception('下载不完整（$received/${asset.size} 字节）');
        }
        return file;
      } catch (e) {
        lastError = e;
        if (await file.exists()) await file.delete();
      }
    }
    throw Exception('下载失败：$lastError');
  }

  Map<String, dynamic> _decode(List<int> bytes) {
    final decoded = json.decode(utf8.decode(bytes, allowMalformed: true));
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw Exception('返回结构无法解析');
  }
}
