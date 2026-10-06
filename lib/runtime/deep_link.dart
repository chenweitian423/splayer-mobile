/// 深链接收：让托管页上的「安装到 CapyPlayer」按钮能直接唤起本 App。
///
/// 托管页（happy-capy `/ext/`）给每张卡片挂的是
/// `com.feifeiduck.capyplayer://add-widget?data=base64url(js 直链)`。
/// 系统按 scheme 找 App，所以原生侧必须声明同名 scheme，收到之后透传给这里。
///
/// ★ 冷启动与热启动都要收：热启动走 `onNewIntent`（Android）/`open url`（iOS），
/// 冷启动时 Dart 还没挂上 handler，原生侧先存起来，等这里 `getInitialLink` 取。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeepLinkService {
  DeepLinkService._();

  static const MethodChannel _channel = MethodChannel('splayer/deeplink');

  /// 待处理的链接；`null` 表示没有。界面监听它就能拿到外部传来的地址。
  static final ValueNotifier<String?> pending = ValueNotifier<String?>(null);

  /// 装上通道。桌面/测试环境没有原生实现，静默跳过即可。
  static Future<void> install() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onLink') {
        final value = call.arguments?.toString() ?? '';
        if (value.isNotEmpty) pending.value = value;
      }
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null && initial.isNotEmpty) pending.value = initial;
    } on MissingPluginException {
      // 平台侧没实现（测试、桌面）——不影响其它功能。
    } catch (_) {
      // 其余异常也不该拦住启动。
    }
  }

  /// 标记已经处理掉当前链接（防止界面重建时重复导入）。
  static void consume() => pending.value = null;
}
