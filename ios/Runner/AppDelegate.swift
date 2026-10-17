import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var mobilePlatform: MobilePlatform?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      do { mobilePlatform = try MobilePlatform(controller: controller) }
      catch { NSLog("Future Notes native storage initialization failed; no library fallback was selected.") }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
