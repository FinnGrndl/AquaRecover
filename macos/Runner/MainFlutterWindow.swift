import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Below this size the editor, movie editor and logbook no longer fit
    // their controls.
    self.contentMinSize = NSSize(width: 480, height: 360)

    RegisterGeneratedPlugins(registry: flutterViewController)
    RawBridge.register(binaryMessenger: flutterViewController.engine.binaryMessenger)
    MacMediaProcessor.register(binaryMessenger: flutterViewController.engine.binaryMessenger)
    MacPhotoPicker.register(viewController: flutterViewController)

    super.awakeFromNib()
  }
}
