import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceTokenString: String?
  private var pushChannel: FlutterMethodChannel?
  private var flChannel: FlutterMethodChannel?
  private var lastUserInteractionAt: Date = Date()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
      DispatchQueue.main.async {
        application.registerForRemoteNotifications()
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let controller = engineBridge.rootViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.anora.push",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }

      switch call.method {
      case "getDeviceToken":
        result(self.deviceTokenString)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    pushChannel = channel

    let fl = FlutterMethodChannel(
      name: "com.anorahealth.anora/fl",
      binaryMessenger: controller.binaryMessenger
    )

    UIDevice.current.isBatteryMonitoringEnabled = true
    fl.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "isDeviceCharging":
        let state = UIDevice.current.batteryState
        result(state == .charging || state == .full)
      case "isDeviceIdle":
        // Consider idle if app is not active or user has been inactive for 15+ min.
        let inactiveFor = Date().timeIntervalSince(self.lastUserInteractionAt)
        let appActive = UIApplication.shared.applicationState == .active
        result((!appActive) || inactiveFor > 900)
      case "recordUserInteraction":
        self.lastUserInteractionAt = Date()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    flChannel = fl
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    deviceTokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    deviceTokenString = nil
  }
}
