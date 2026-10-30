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

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
