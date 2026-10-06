package com.chenweitian.splayer_mobile

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 组件安装深链接收：托管页上的「安装」按钮是
 * `com.feifeiduck.capyplayer://add-widget?data=...`，系统按 scheme 找到本 Activity，
 * 这里把整条 URL 透给 Dart（`splayer/deeplink` 通道），由 Dart 侧解码 data 并下载安装。
 *
 * 冷启动时 Dart 还没挂上 handler，所以先存进 pendingLink，等 Dart 来取。
 */
class MainActivity : FlutterActivity() {

    private var pendingLink: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        extractLink(intent)?.let { pendingLink = it }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractLink(intent) ?: return
        val active = channel
        if (active == null) {
            pendingLink = link
        } else {
            active.invokeMethod("onLink", link)
        }
    }

    private fun extractLink(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        return intent.dataString?.takeIf { it.isNotEmpty() }
    }

    companion object {
        private const val CHANNEL = "splayer/deeplink"
    }
}
