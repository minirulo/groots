import Foundation

/// XPC protocol shared between the KuboHelper service and the Runner client.
/// Both targets must compile this exact definition.
@objc protocol KuboHelperProtocol {
    /// Set up the repo and launch the kubo daemon.
    /// - Parameters:
    ///   - repoPath: Absolute path to the IPFS repo directory (Application Support).
    ///   - swarmKey: Contents of the private swarm key file.
    ///   - gatewayPort: Local HTTP gateway port (dev=8180, prod=8280).
    ///   - reply: Called with (success, errorMessage). errorMessage is nil on success.
    func start(repoPath: String, swarmKey: String, gatewayPort: Int, reply: @escaping (Bool, String?) -> Void)

    /// Send SIGTERM to the daemon and wait for it to exit.
    func stop(reply: @escaping (Bool) -> Void)

    /// Returns whether the daemon process is currently running.
    func status(reply: @escaping (Bool) -> Void)
}
