import Foundation
import os.log

private let log = OSLog(subsystem: "com.rce-studio.groots", category: "KuboXPCClient")

/// Manages the NSXPCConnection to the embedded KuboHelper XPC service.
final class KuboXPCClient {

    static let shared = KuboXPCClient()

    private static let serviceIdentifier = "com.rce-studio.groots.kubo-helper"

    private var connection: NSXPCConnection?

    private init() {}

    // MARK: - Public

    func start(repoPath: String, swarmKey: String, gatewayPort: Int, completion: @escaping (Bool, String?) -> Void) {
        proxy { proxy in
            proxy.start(repoPath: repoPath, swarmKey: swarmKey, gatewayPort: gatewayPort) { success, error in
                completion(success, error)
            }
        } onError: { error in
            completion(false, error)
        }
    }

    func stop(completion: @escaping (Bool) -> Void) {
        proxy { proxy in
            proxy.stop { success in completion(success) }
        } onError: { _ in
            completion(false)
        }
    }

    func status(completion: @escaping (Bool) -> Void) {
        proxy { proxy in
            proxy.status { running in completion(running) }
        } onError: { _ in
            completion(false)
        }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    // MARK: - Private

    private func makeConnection() -> NSXPCConnection {
        let conn = NSXPCConnection(serviceName: Self.serviceIdentifier)
        conn.remoteObjectInterface = NSXPCInterface(with: KuboHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            os_log("XPC connection invalidated", log: log, type: .info)
            self?.connection = nil
        }
        conn.interruptionHandler = { [weak self] in
            os_log("XPC connection interrupted", log: log, type: .error)
            self?.connection = nil
        }
        conn.resume()
        return conn
    }

    private func proxy(
        _ block: @escaping (KuboHelperProtocol) -> Void,
        onError: @escaping (String) -> Void
    ) {
        if connection == nil { connection = makeConnection() }

        let proxy = connection?.remoteObjectProxyWithErrorHandler { error in
            os_log("XPC proxy error: %{public}@", log: log, type: .error, error.localizedDescription)
            onError(error.localizedDescription)
        } as? KuboHelperProtocol

        guard let proxy else {
            onError("Failed to obtain XPC proxy for \(Self.serviceIdentifier)")
            return
        }
        block(proxy)
    }
}
