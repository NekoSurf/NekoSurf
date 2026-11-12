import CloudKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // What iOS says of pushes, for the iCloud sync log; CKSyncEngine handles
  // the pushes themselves.

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    if let sync = CloudSyncChannel.sync { Task { await sync.registeredForPushes(nil) } }
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    if let sync = CloudSyncChannel.sync { Task { await sync.registeredForPushes(error) } }
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let fromICloud = CKNotification(fromRemoteNotificationDictionary: userInfo) != nil
    if let sync = CloudSyncChannel.sync { Task { await sync.pushCame(fromICloud: fromICloud) } }
    super.application(
      application, didReceiveRemoteNotification: userInfo,
      fetchCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CloudSync") {
      CloudSyncChannel.register(with: registrar)
    }
  }
}

/// When the scene goes away (the app is swiped out of the app switcher, or
/// iOS discards it), Flutter shuts Dart down. Video players' native threads
/// (mpv) can still call into Dart at that moment, which aborts the app and
/// shows up as a crash. Nothing is on screen anymore and a new scene would
/// start a fresh engine anyway, so end the process before that teardown.
class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidDisconnect(_ scene: UIScene) {
    UserDefaults.standard.synchronize()
    _exit(0)
  }
}
