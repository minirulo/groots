import FlutterMacOS
import Foundation

/// Bridges the "groots/kubo" Flutter MethodChannel to KuboXPCClient.
///
/// Dart API:
///   invokeMethod("start", {"repo_path": String, "swarm_key": String})
///     → {"success": Bool, "error": String?}
///   invokeMethod("stop")
///     → void
///   invokeMethod("status")
///     → {"running": Bool}
final class KuboMethodChannel {

    static let channelName = "groots/kubo"

    private let channel: FlutterMethodChannel

    /// Called whenever the daemon transitions between running and stopped states.
    /// AppDelegate uses this to keep its cached state in sync for the dock menu.
    var onStateChanged: ((Bool) -> Void)?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler(handle(_:result:))
    }

    // MARK: - Native → Flutter

    /// Ask the Dart side to start the daemon (used by the dock menu).
    func invokeStart() {
        channel.invokeMethod("startFromNative", arguments: nil)
    }

    /// Ask the Dart side to stop the daemon (used by the dock menu).
    func invokeStop() {
        channel.invokeMethod("stopFromNative", arguments: nil)
    }

    // MARK: - Handler

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            handleStart(call, result: result)
        case "stop":
            KuboXPCClient.shared.stop { [weak self] _ in
                self?.onStateChanged?(false)
                result(nil)
            }
        case "status":
            KuboXPCClient.shared.status { running in
                result(["running": running])
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleStart(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard
            let args = call.arguments as? [String: Any],
            let repoPath = args["repo_path"] as? String,
            let swarmKey = args["swarm_key"] as? String
        else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "start requires {repo_path: String, swarm_key: String}",
                details: nil
            ))
            return
        }

        KuboXPCClient.shared.start(repoPath: repoPath, swarmKey: swarmKey) { [weak self] success, error in
            if success { self?.onStateChanged?(true) }
            result(["success": success, "error": error as Any])
        }
    }
}
