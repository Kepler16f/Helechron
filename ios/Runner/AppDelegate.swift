import Flutter
import UIKit
import workmanager_apple
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingRoute: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 后台刷新（成绩变动 / DDL 提醒）
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "top.celechron.aelechron.backgroundScholarFetch",
      frequency: NSNumber(value: 15 * 60))
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // 前台通知展示
    UNUserNotificationCenter.current().delegate = self

    setupWidgetMethodChannel()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func setupWidgetMethodChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    let widgetChannel = FlutterMethodChannel(
      name: "top.celechron.celechron/widget",
      binaryMessenger: controller.binaryMessenger
    )
    widgetChannel.setMethodCallHandler { [weak self] (call, result) in
      let defaults = UserDefaults(suiteName: "group.top.celechron.aelechron") ?? UserDefaults.standard
      switch call.method {
      case "updateCourseWidget":
        if let args = call.arguments as? [String: Any] {
          if let json = args["coursesJson"] as? String {
            defaults.set(json, forKey: "coursesJson")
          }
          if let lead = args["leadWindowMinutes"] as? Int {
            defaults.set(lead, forKey: "leadWindowMinutes")
          }
        }
        #if canImport(WidgetKit)
        if #available(iOS 14.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        result(true)

      case "updatePaymentCodeWidget":
        if let args = call.arguments as? [String: Any] {
          if let code = args["paymentCode"] as? String {
            defaults.set(code, forKey: "paymentCode")
          }
          if let name = args["displayName"] as? String {
            defaults.set(name, forKey: "displayName")
          }
        }
        #if canImport(WidgetKit)
        if #available(iOS 14.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        result(true)

      case "setWidgetData":
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String,
           let value = args["value"] as? String {
          defaults.set(value, forKey: key)
        }
        result(true)

      case "consumePendingRoute":
        let route = self?.pendingRoute
        self?.pendingRoute = nil
        result(route)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    if url.scheme == "celechron" {
      let target = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      if !target.isEmpty {
        pendingRoute = target
        if let controller = window?.rootViewController as? FlutterViewController {
          let channel = FlutterMethodChannel(
            name: "top.celechron.celechron/widget",
            binaryMessenger: controller.binaryMessenger
          )
          channel.invokeMethod("onWidgetRoute", arguments: ["target": target])
        }
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
