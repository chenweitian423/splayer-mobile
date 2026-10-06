import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var linkChannel: FlutterMethodChannel?
  private var pendingLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "splayer/deeplink",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "getInitialLink" {
          result(self?.pendingLink)
          self?.pendingLink = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      linkChannel = channel
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 组件安装深链：托管页的「安装」按钮点击后落到这里。
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let link = url.absoluteString
    if let channel = linkChannel {
      channel.invokeMethod("onLink", arguments: link)
    } else {
      // 冷启动：Dart 侧还没挂上 handler，先存着等它来取。
      pendingLink = link
    }
    return super.application(app, open: url, options: options)
  }
}
