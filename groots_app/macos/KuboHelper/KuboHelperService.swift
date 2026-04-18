import Foundation
import os.log

private let log = OSLog(subsystem: "com.rce-studio.groots.kubo-helper", category: "KuboHelperService")

final class KuboHelperService: NSObject, KuboHelperProtocol {

    private static let apiPort = 5101
    private static let gatewayPort = 8180
    private static let swarmPort = 4101

    private var daemonProcess: Process?

    // MARK: - KuboHelperProtocol

    func start(repoPath: String, swarmKey: String, reply: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Use the XPC service's own sandbox container rather than the
                // caller-supplied path. With app-sandbox = true (required for App
                // Store), the XPC service has its own container and cannot write
                // to the parent app's container.
                let ownRepoPath = self.sandboxedRepoPath()
                try self.setupAndLaunch(repoPath: ownRepoPath, swarmKey: swarmKey)
                reply(true, nil)
            } catch {
                os_log("start failed: %{public}@", log: log, type: .error, error.localizedDescription)
                reply(false, error.localizedDescription)
            }
        }
    }

    private func sandboxedRepoPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let repoURL = appSupport.appendingPathComponent("ipfs-repo")
        try? FileManager.default.createDirectory(at: repoURL,
                                                  withIntermediateDirectories: true)
        return repoURL.path
    }

    func stop(reply: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let process = self.daemonProcess, process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            self.daemonProcess = nil
            os_log("daemon stopped", log: log, type: .info)
            reply(true)
        }
    }

    func status(reply: @escaping (Bool) -> Void) {
        reply(daemonProcess?.isRunning == true)
    }

    // MARK: - Private

    private func setupAndLaunch(repoPath: String, swarmKey: String) throws {
        // Fast path: if our own tracked process is running, nothing to do.
        if daemonProcess?.isRunning == true {
            os_log("daemon already running (tracked) — adopting", log: log, type: .info)
            return
        }

        // If the API is already answering (e.g. daemon survived an app restart),
        // adopt it without touching the repo — running ipfs init while the daemon
        // is live causes an immediate error.
        if isDaemonReachable() {
            os_log("daemon already reachable via API — adopting without re-init", log: log, type: .info)
            return
        }

        let kuboURL = try bundledKuboURL()

        // Kill any orphaned daemon if the swarm key on disk differs from what we received.
        let keyPath = (repoPath as NSString).appendingPathComponent("swarm.key")
        let existingKey = try? String(contentsOfFile: keyPath, encoding: .utf8)
        if existingKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            != swarmKey.trimmingCharacters(in: .whitespacesAndNewlines) {
            os_log("swarm key changed — stopping any running daemon", log: log, type: .info)
            killOrphanedDaemon()
        }

        try initRepo(kuboURL: kuboURL, repoPath: repoPath)
        try writeSwarmKey(content: swarmKey, to: keyPath)
        try configureNode(kuboURL: kuboURL, repoPath: repoPath)

        let daemon = Process()
        daemon.executableURL = kuboURL
        daemon.arguments = ["daemon", "--migrate=true"]
        daemon.environment = [
            "IPFS_PATH": repoPath,
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin",
        ]

        // Pipe output to os_log so it shows in Console.app
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        daemon.standardOutput = stdoutPipe
        daemon.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                os_log("[kubo] %{public}@", log: log, type: .debug, line)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                os_log("[kubo err] %{public}@", log: log, type: .error, line)
            }
        }

        daemon.terminationHandler = { [weak self] process in
            os_log("daemon exited with code %d", log: log, type: .info, process.terminationStatus)
            self?.daemonProcess = nil
        }

        try daemon.run()
        daemonProcess = daemon
        os_log("daemon launched (pid %d)", log: log, type: .info, daemon.processIdentifier)
    }

    private func bundledKuboURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "ipfs", withExtension: nil) else {
            throw KuboError.binaryNotFound
        }
        return url
    }

    private func initRepo(kuboURL: URL, repoPath: String) throws {
        let result = run(kuboURL, args: ["init", "--profile=server"], repoPath: repoPath)
        // These outputs mean the repo (or daemon) already exists — not an error.
        let benign = result.output.contains("already") || result.output.contains("daemon is running")
        if result.exitCode != 0 && !benign {
            throw KuboError.commandFailed(
                "ipfs init failed (exit \(result.exitCode)): \(result.output)"
            )
        }
    }

    private func writeSwarmKey(content: String, to path: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func configureNode(kuboURL: URL, repoPath: String) throws {
        func cfg(_ args: [String]) {
            _ = run(kuboURL, args: ["config"] + args, repoPath: repoPath)
        }

        cfg(["Addresses.API", "/ip4/127.0.0.1/tcp/\(Self.apiPort)"])
        cfg(["Addresses.Gateway", "/ip4/127.0.0.1/tcp/\(Self.gatewayPort)"])
        cfg(["--json", "API.HTTPHeaders.Access-Control-Allow-Origin",
             "[\"http://localhost:3000\",\"http://127.0.0.1:3000\",\"https://webui.ipfs.io\"]"])
        cfg(["--json", "API.HTTPHeaders.Access-Control-Allow-Methods",
             "[\"PUT\",\"POST\",\"GET\"]"])
        cfg(["Addresses.Swarm", "--json",
             "[\"/ip4/0.0.0.0/tcp/\(Self.swarmPort)\",\"/ip6/::/tcp/\(Self.swarmPort)\"]"])
        cfg(["AutoConf.Enabled", "--bool", "false"])
        cfg(["Discovery.MDNS.Enabled", "--bool", "true"])
        cfg(["--json", "Swarm.AddrFilters", "[]"])

        _ = run(kuboURL, args: ["bootstrap", "rm", "--all"], repoPath: repoPath)
        os_log("node configured (API :%d, Gateway :%d, Swarm :%d)",
               log: log, type: .info,
               Self.apiPort, Self.gatewayPort, Self.swarmPort)
    }

    /// Returns true if the Kubo API is already answering on the expected port.
    private func isDaemonReachable() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(Self.apiPort)/api/v0/id") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        let sema = DispatchSemaphore(value: 0)
        var reachable = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                reachable = true
            }
            sema.signal()
        }.resume()
        sema.wait()
        return reachable
    }

    private func killOrphanedDaemon() {
        // Try graceful HTTP shutdown first (best-effort).
        if let url = URL(string: "http://127.0.0.1:\(Self.apiPort)/api/v0/shutdown") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 5
            let sema = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: req) { _, _, _ in sema.signal() }.resume()
            sema.wait()
        }

        // Also terminate any tracked process.
        if let p = daemonProcess, p.isRunning {
            p.terminate()
            p.waitUntilExit()
            daemonProcess = nil
        }

        // Give the port a moment to be released.
        Thread.sleep(forTimeInterval: 1.0)
    }

    @discardableResult
    private func run(_ url: URL, args: [String], repoPath: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = url
        process.arguments = args
        // Include HOME so Go's os.UserHomeDir() and any stdlib calls that rely
        // on it don't fail silently. Strip everything else to keep the env clean.
        process.environment = [
            "IPFS_PATH": repoPath,
            "HOME": NSHomeDirectory(),
            "PATH": "/usr/bin:/bin",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        process.waitUntilExit()

        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Merge both streams so no output is silently discarded.
        let combined = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        return (process.terminationStatus, combined)
    }
}

// MARK: - Error

enum KuboError: LocalizedError {
    case binaryNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "kubo binary not found in XPC service bundle (expected Resources/ipfs)"
        case .commandFailed(let msg):
            return msg
        }
    }
}
