import Flutter
import UIKit
import AVKit
import AVFoundation
import SafariServices
import workmanager_apple
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

private final class ZhiyunAVPlayerViewController: AVPlayerViewController {
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    return [.landscapeLeft, .landscapeRight, .portrait]
  }

  override var shouldAutorotate: Bool {
    return true
  }

  override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
    return .landscapeRight
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, AVPlayerViewControllerDelegate {
  private var pendingRoute: String?
  private var documentInteractionController: UIDocumentInteractionController?
  private weak var presentingVideoHostController: UIViewController?
  private var activePipPlayerController: AVPlayerViewController?

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

      case "openFileWithSystem":
        if let args = call.arguments as? [String: Any],
           let filePath = args["filePath"] as? String,
           !filePath.isEmpty {
          let ok = self?.openFileWithSystem(filePath: filePath, controller: controller) ?? false
          result(ok)
        } else {
          result(false)
        }

      case "openInAppVideoPlayer":
        if let args = call.arguments as? [String: Any],
           let urlStr = args["url"] as? String,
           !urlStr.isEmpty {
          let token = args["token"] as? String
          let livingroomUrl = args["livingroomUrl"] as? String
          let rawStreams = args["streams"] as? [[String: Any]] ?? []
          let streamUrls = rawStreams.compactMap { ($0["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
          let ok = self?.openInAppVideoPlayer(
            urlStr: urlStr,
            streamUrls: streamUrls,
            livingroomUrl: livingroomUrl,
            token: token,
            controller: controller
          ) ?? false
          result(ok)
        } else {
          result(false)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func openFileWithSystem(filePath: String, controller: UIViewController) -> Bool {
    let fileUrl: URL
    if filePath.hasPrefix("file://"), let parsed = URL(string: filePath) {
      fileUrl = parsed
    } else {
      fileUrl = URL(fileURLWithPath: filePath)
    }
    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      return false
    }
    DispatchQueue.main.async { [weak self] in
      let docController = UIDocumentInteractionController(url: fileUrl)
      self?.documentInteractionController = docController
      if !docController.presentOptionsMenu(from: controller.view.bounds, in: controller.view, animated: true) {
        let activityVC = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
        if let pop = activityVC.popoverPresentationController {
          pop.sourceView = controller.view
          pop.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        }
        controller.present(activityVC, animated: true)
      }
    }
    return true
  }

  private func isDirectStreamUrl(_ rawUrl: String) -> Bool {
    let lower = rawUrl.lowercased()
    if lower.contains("livingroom") {
      return false
    }
    return lower.contains(".mp4") || lower.contains(".m3u8") || lower.contains(".flv") || lower.contains(".ts")
  }

  private func openInAppVideoPlayer(
    urlStr: String,
    streamUrls: [String] = [],
    livingroomUrl: String? = nil,
    token: String? = nil,
    controller: UIViewController
  ) -> Bool {
    var candidates: [URL] = []
    var seen = Set<String>()
    func addCandidate(_ raw: String) {
      let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, isDirectStreamUrl(trimmed), seen.insert(trimmed).inserted,
            let parsed = URL(string: trimmed) else { return }
      candidates.append(parsed)
    }
    streamUrls.forEach(addCandidate)
    addCandidate(urlStr)

    let fallbackStr = (livingroomUrl?.isEmpty == false ? livingroomUrl : nil) ?? urlStr
    guard !candidates.isEmpty || URL(string: fallbackStr) != nil else {
      return false
    }

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if let streamUrl = candidates.first {
        do {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
          try session.setActive(true)
        } catch {
          // ignore audio session warning
        }
        var headers = [
          "Referer": "https://classroom.zju.edu.cn/",
          "Origin": "https://classroom.zju.edu.cn"
        ]
        if let tk = token, !tk.isEmpty {
          headers["Cookie"] = "_token=\(tk); token=\(tk)"
          headers["Authorization"] = "Bearer \(tk)"
        }
        let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        let playerVC = ZhiyunAVPlayerViewController()
        playerVC.player = player
        playerVC.allowsPictureInPicturePlayback = true
        if #available(iOS 14.2, *) {
          playerVC.canStartPictureInPictureAutomaticallyFromInline = true
        }
        playerVC.entersFullScreenWhenPlaybackBegins = true
        playerVC.exitsFullScreenWhenPlaybackEnds = false
        playerVC.delegate = self
        self.presentingVideoHostController = controller
        self.activePipPlayerController = playerVC
        controller.present(playerVC, animated: true) {
          player.play()
        }
      } else if let webUrl = URL(string: fallbackStr) {
        let safariVC = SFSafariViewController(url: webUrl)
        controller.present(safariVC, animated: true)
      }
    }
    return true
  }

  func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
    activePipPlayerController = playerViewController
  }

  func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
    if activePipPlayerController === playerViewController && playerViewController.presentingViewController == nil {
      activePipPlayerController = nil
    }
  }

  func playerViewController(
    _ playerViewController: AVPlayerViewController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    if playerViewController.presentingViewController != nil {
      completionHandler(true)
      return
    }
    if let host = presentingVideoHostController {
      host.present(playerViewController, animated: true) {
        completionHandler(true)
      }
    } else {
      completionHandler(false)
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
