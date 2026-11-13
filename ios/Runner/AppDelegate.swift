import CloudKit
import CoreImage
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppSwitcherCover.watch()
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

/// With "Hide in the app switcher" on, blurs the app while it isn't active,
/// so the app switcher's picture of it shows nothing readable of what's open.
/// Watched through notifications, so FlutterSceneDelegate's own handling of
/// the same moments stays as it is.
enum AppSwitcherCover {
  /// The setting, as shared_preferences keeps it (SettingsProvider).
  private static let settingKey = "flutter.coverInAppSwitcher"
  private static let tag = 0x6E656B6F

  /// What's on screen, drawn a few dozen pixels wide, blurred and
  /// stretched back: nothing in it can be made out, not even a figure's
  /// outline, and it costs next to nothing. Dimmed, so bright pictures don't
  /// wash it out.
  private static func blurredCopy(of window: UIWindow) -> UIView {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 0.06
    // Opaque, filled first: any of it left undrawn mustn't let what's
    // open show through.
    format.opaque = true
    let tiny = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
      UIColor.black.setFill()
      context.fill(window.bounds)
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
    }
    let cover = UIImageView(image: blurred(tiny))
    cover.backgroundColor = .black
    cover.frame = window.bounds
    cover.contentMode = .scaleToFill
    cover.tag = tag
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let dim = UIView(frame: cover.bounds)
    dim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.addSubview(dim)
    return cover
  }

  /// [image], blurred by a few of its pixels, edges and all.
  private static func blurred(_ image: UIImage) -> UIImage {
    guard let input = CIImage(image: image) else { return image }
    let output = input.clampedToExtent().applyingGaussianBlur(sigma: 3)
      .cropped(to: input.extent)
    guard let cg = CIContext().createCGImage(output, from: input.extent) else {
      return image
    }
    return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
  }

  static func watch() {
    let center = NotificationCenter.default
    // Leaving: the blur fades in as the app shrinks into the switcher.
    center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { note in
      guard UserDefaults.standard.bool(forKey: settingKey),
        let window = (note.object as? UIWindowScene)?.windows.first,
        window.viewWithTag(tag) == nil
      else { return }
      let cover = blurredCopy(of: window)
      cover.alpha = 0
      window.addSubview(cover)
      UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
        cover.alpha = 1
      }
    }
    // Gone: iOS takes the switcher's picture of the app right after this,
    // so the blur must be whole by then, however far it had faded in.
    center.addObserver(
      forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main
    ) { note in
      (note.object as? UIWindowScene)?.windows.forEach {
        guard let cover = $0.viewWithTag(tag) else { return }
        cover.layer.removeAllAnimations()
        cover.alpha = 1
      }
    }
    // Back: it fades out. Untagged at once, so leaving again meanwhile
    // brings a fresh one rather than finding this one on its way out.
    center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { note in
      (note.object as? UIWindowScene)?.windows.forEach {
        guard let cover = $0.viewWithTag(tag) else { return }
        cover.tag = 0
        UIView.animate(
          withDuration: 0.25, delay: 0, options: [.curveEaseIn, .beginFromCurrentState],
          animations: { cover.alpha = 0 },
          completion: { _ in cover.removeFromSuperview() })
      }
    }
  }
}
