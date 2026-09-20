import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
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

    super.awakeFromNib()
  }
}
