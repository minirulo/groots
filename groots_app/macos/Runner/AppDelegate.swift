import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  private var kuboChannel: KuboMethodChannel?

  /// Cached running state — updated via KuboMethodChannel.onStateChanged and
  /// by the status-polling timer so the dock menu always reflects reality.
  private var ipfsRunning = false
  private var statusTimer: Timer?

  private var vinylChannel: VinylRecorderChannel?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else { return }

    let channel = KuboMethodChannel(messenger: controller.engine.binaryMessenger)
    channel.onStateChanged = { [weak self] running in
      DispatchQueue.main.async { self?.ipfsRunning = running }
    }
    kuboChannel = channel

    vinylChannel = VinylRecorderChannel(messenger: controller.engine.binaryMessenger)

    // Poll XPC status every 3 s so the dock menu stays accurate even when the
    // daemon is started/stopped from the Flutter UI instead of the dock menu.
    statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
      KuboXPCClient.shared.status { running in
        DispatchQueue.main.async { self?.ipfsRunning = running }
      }
    }
  }

  // MARK: - Dock menu

  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()

    let title = ipfsRunning ? "Stop IPFS Node" : "Start IPFS Node"
    let action = ipfsRunning ? #selector(stopIPFS) : #selector(startIPFS)
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)

    return menu
  }

  @objc private func startIPFS() {
    kuboChannel?.invokeStart()
  }

  @objc private func stopIPFS() {
    kuboChannel?.invokeStop()
  }

  // MARK: - App lifecycle

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    statusTimer?.invalidate()
    KuboXPCClient.shared.invalidate()
  }
}
