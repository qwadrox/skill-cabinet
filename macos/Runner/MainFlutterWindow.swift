import Cocoa
import FlutterMacOS
import macos_window_utils
import Sparkle

class MainFlutterWindow: NSWindow {
  private var appUpdater: AppUpdater?

  override func awakeFromNib() {
    // macos_window_utils hosts the Flutter view so the sidebar can use real
    // NSVisualEffectView vibrancy and the toolbar can be unified.
    let windowFrame = self.frame
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController()
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(registry: macOSWindowUtilsViewController.flutterViewController)

    // Same initial and minimum size as the Native SDK version.
    self.setContentSize(NSSize(width: 1120, height: 720))
    self.contentMinSize = NSSize(width: 960, height: 520)
    self.center()
    self.title = "Skill Cabinet"

    appUpdater = AppUpdater(messenger: macOSWindowUtilsViewController.flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
    appUpdater?.start()
  }
}

// Sparkle owns the native update UI, signature verification, installation,
// and relaunch. Flutter only exposes the check action and its enabled state.
private final class AppUpdater {
  private let controller = SPUStandardUpdaterController(
    startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
  private let channel: FlutterMethodChannel
  private var observation: NSKeyValueObservation?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "skill_cabinet/app_updates", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "canCheckForUpdates":
        result(self.controller.updater.canCheckForUpdates)
      case "checkForUpdates":
        if self.controller.updater.canCheckForUpdates {
          self.controller.checkForUpdates(nil)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
      self?.channel.invokeMethod("canCheckForUpdatesChanged", arguments: updater.canCheckForUpdates)
    }
  }

  func start() {
    controller.startUpdater()
  }
}
