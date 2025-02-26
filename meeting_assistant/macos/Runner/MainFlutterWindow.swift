import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Enable window resizing and fullscreen capabilities
    self.styleMask.insert(.resizable)
    self.collectionBehavior = [.fullScreenPrimary]
    self.isReleasedWhenClosed = false
    self.minSize = NSSize(width: 640, height: 480)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
