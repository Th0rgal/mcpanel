//
//  SSHService.swift
//  MCPanel
//
//  SSH command execution service using the system ssh command
//

import Foundation

// MARK: - SSH Error

enum SSHError: Error, LocalizedError {
    case connectionFailed(String)
    case commandFailed(String)
    case timeout
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "SSH connection failed: \(message)"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .timeout:
            return "SSH operation timed out"
        case .invalidConfiguration:
            return "Invalid SSH configuration"
        }
    }
}

// MARK: - SSH Service

actor SSHService {
    private let server: Server
    private var isConnected = false

    init(server: Server) {
        self.server = server
    }

    // MARK: - Connection Test

    func testConnection() async throws -> Bool {
        let result = try await execute("echo 'connected'")
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "connected"
    }

    // MARK: - Command Execution

    func execute(_ command: String, timeout: TimeInterval = 30) async throws -> String {
        let (sshCommand, stopAccessing) = buildSSHCommand(remoteCommand: command)
        defer { stopAccessing() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = sshCommand

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let logger = DebugLogger.shared
        let shortCmd = String(command.prefix(60))
        logger.log("execute: Starting process for '\(shortCmd)...'", category: .ssh, verbose: true)

        // Accumulate output data asynchronously to avoid pipe buffer blocking
        // Use a class wrapper to safely capture mutable state in concurrent closures
        final class DataAccumulator: @unchecked Sendable {
            var data = Data()
            let lock = NSLock()
            func append(_ newData: Data) {
                lock.lock()
                data.append(newData)
                lock.unlock()
            }
            func getData() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }

        let outputAccumulator = DataAccumulator()
        let errorAccumulator = DataAccumulator()

        // Read output asynchronously to prevent pipe buffer from filling
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputAccumulator.append(data)
            }
        }

        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                errorAccumulator.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            logger.log("execute: Process launch failed: \(error)", category: .ssh)
            throw SSHError.connectionFailed(error.localizedDescription)
        }

        logger.log("execute: Process running, waiting up to \(Int(timeout))s", category: .ssh, verbose: true)

        // Wait with timeout
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        // Clean up handlers
        outputHandle.readabilityHandler = nil
        errorHandle.readabilityHandler = nil

        if process.isRunning {
            logger.log("execute: Process timed out after \(Int(timeout))s, terminating", category: .ssh)
            process.terminate()
            throw SSHError.timeout
        }

        // Read any remaining data
        outputAccumulator.append(outputHandle.readDataToEndOfFile())
        errorAccumulator.append(errorHandle.readDataToEndOfFile())

        let output = String(data: outputAccumulator.getData(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorAccumulator.getData(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && !errorOutput.isEmpty {
            logger.log("execute: Command failed with status \(process.terminationStatus): \(errorOutput.prefix(200))", category: .ssh)
            throw SSHError.commandFailed(errorOutput)
        }

        logger.log("execute: Success, got \(output.count) bytes", category: .ssh, verbose: true)
        isConnected = true
        return output
    }

    // MARK: - Streaming Output

    func stream(_ command: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let (sshCommand, stopAccessing) = buildSSHCommand(remoteCommand: command)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = sshCommand

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    if let line = String(data: data, encoding: .utf8) {
                        continuation.yield(line)
                    }
                }

                process.terminationHandler = { _ in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    stopAccessing()  // Release security-scoped resource when process ends
                    continuation.finish()
                }

                // Handle stream cancellation (consumer stops iterating early)
                continuation.onTermination = { @Sendable _ in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    if process.isRunning {
                        process.terminate()
                    }
                    stopAccessing()  // Release security-scoped resource on cancellation
                }

                do {
                    try process.run()
                } catch {
                    stopAccessing()  // Release on error too
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Build SSH command arguments and return a closure to release security-scoped resources
    private func buildSSHCommand(remoteCommand: String) -> (args: [String], stopAccessing: () -> Void) {
        var args: [String] = []

        // Resolve SSH key path using security-scoped bookmark if available
        let (keyPath, stopAccessing) = server.resolveSSHKeyPath()
        if let path = keyPath {
            args.append(contentsOf: ["-i", path])
        }

        // SSH options for non-interactive use
        // Use ControlMaster to share SSH connections and avoid rate limiting
        // Use app's temp directory for sandbox compatibility
        let tempDir = FileManager.default.temporaryDirectory.path
        let controlPath = "\(tempDir)/mcpanel-ssh-\(server.host)-\(server.sshUsername)"
        args.append(contentsOf: [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=60"
        ])

        // Port if non-standard
        if server.sshPort != 22 {
            args.append(contentsOf: ["-p", String(server.sshPort)])
        }

        // User@host
        args.append("\(server.sshUsername)@\(server.host)")

        // Remote command
        args.append(remoteCommand)

        return (args, stopAccessing)
    }
}

// MARK: - Convenience Extensions

extension SSHService {
    /// List files in a directory
    func listFiles(path: String) async throws -> [FileItem] {
        let output = try await execute("ls -la '\(path)'")
        let lines = output.components(separatedBy: .newlines)

        return lines.compactMap { line in
            FileItem.parse(line: line, parentPath: path)
        }
    }

    /// List plugins in the plugins directory
    func listPlugins() async throws -> [Plugin] {
        let pluginsPath = server.effectivePluginsPath
        let output = try await execute("ls -la '\(pluginsPath)'")
        let lines = output.components(separatedBy: .newlines)

        var plugins: [Plugin] = []

        for line in lines {
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }

            let size = Int64(components[4]) ?? 0
            let fileName = components[8...].joined(separator: " ")

            if let plugin = Plugin.fromFileName(fileName, fileSize: size) {
                plugins.append(plugin)
            }
        }

        return plugins.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Enable or disable a plugin by renaming
    func togglePlugin(_ plugin: Plugin) async throws {
        let pluginsPath = server.effectivePluginsPath
        let currentPath = "\(pluginsPath)/\(plugin.fileName)"
        let newFileName = plugin.isEnabled ? plugin.disabledFileName : plugin.enabledFileName
        let newPath = "\(pluginsPath)/\(newFileName)"

        _ = try await execute("mv '\(currentPath)' '\(newPath)'")
    }

    /// Check if the server is running (via systemd)
    func isServerRunning() async throws -> Bool {
        guard let unit = server.systemdUnit else {
            return false
        }

        let output = try await execute("systemctl is-active '\(unit)'")
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "active"
    }

    /// Start the server
    func startServer() async throws {
        guard let unit = server.systemdUnit else {
            throw SSHError.invalidConfiguration
        }
        _ = try await execute("systemctl start '\(unit)'")
    }

    /// Stop the server gracefully by sending "stop" command to Minecraft console
    func stopServer() async throws {
        // First, try to send "stop" command via tmux/screen for graceful shutdown
        if let tmuxSession = server.tmuxSession {
            _ = try? await execute("tmux send-keys -t '\(tmuxSession)' 'stop' Enter")
            // Wait for graceful shutdown (up to 30 seconds)
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let isRunning = try? await isServerRunning()
                if isRunning == false { return }
            }
        } else if let screenSession = server.screenSession {
            _ = try? await execute("screen -S '\(screenSession)' -X stuff 'stop\\n'")
            // Wait for graceful shutdown (up to 30 seconds)
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let isRunning = try? await isServerRunning()
                if isRunning == false { return }
            }
        }

        // Fall back to systemctl stop if graceful shutdown didn't work or no session configured
        guard let unit = server.systemdUnit else {
            throw SSHError.invalidConfiguration
        }
        _ = try await execute("systemctl stop '\(unit)'")
    }

    /// Restart the server gracefully
    func restartServer() async throws {
        guard let unit = server.systemdUnit else {
            throw SSHError.invalidConfiguration
        }

        // First, try to send "stop" command via tmux/screen for graceful shutdown
        if let tmuxSession = server.tmuxSession {
            _ = try? await execute("tmux send-keys -t '\(tmuxSession)' 'stop' Enter")
            // Wait for graceful shutdown (up to 30 seconds)
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let isRunning = try? await isServerRunning()
                if isRunning == false { break }
            }
        } else if let screenSession = server.screenSession {
            _ = try? await execute("screen -S '\(screenSession)' -X stuff 'stop\\n'")
            // Wait for graceful shutdown (up to 30 seconds)
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let isRunning = try? await isServerRunning()
                if isRunning == false { break }
            }
        }

        // Restart via systemd (works whether it's running or already stopped)
        _ = try await execute("systemctl restart '\(unit)'")
    }

    /// Get server status details
    func getServerStatus() async throws -> String {
        guard let unit = server.systemdUnit else {
            throw SSHError.invalidConfiguration
        }
        return try await execute("systemctl status '\(unit)' --no-pager")
    }

    /// Detect Minecraft version and server type from logs
    func detectServerInfo() async throws -> (version: String?, serverType: ServerType?) {
        let logPath = "\(server.serverPath)/logs/latest.log"
        let output = try await execute("head -50 '\(logPath)' 2>/dev/null || echo ''")

        var version: String?
        var serverType: ServerType?

        // Parse version from log - look for "server version X.X.X"
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            // Example: "Starting minecraft server version 1.21.11"
            if line.lowercased().contains("server version") {
                let parts = line.components(separatedBy: " ")
                for (index, part) in parts.enumerated() {
                    if part.lowercased() == "version" && index + 1 < parts.count {
                        let potentialVersion = parts[index + 1]
                        // Check if it looks like a version number
                        if potentialVersion.first?.isNumber == true {
                            version = potentialVersion.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                            break
                        }
                    }
                }
            }
            if version != nil { break }
        }

        // Detect server type from log
        let lowerOutput = output.lowercased()
        if lowerOutput.contains("paper version") || lowerOutput.contains("running paper") {
            serverType = .paper
        } else if lowerOutput.contains("purpur version") || lowerOutput.contains("running purpur") {
            serverType = .purpur
        } else if lowerOutput.contains("spigot version") || lowerOutput.contains("running spigot") {
            serverType = .spigot
        } else if lowerOutput.contains("fabric") {
            serverType = .fabric
        } else if lowerOutput.contains("forge") {
            serverType = .forge
        } else if lowerOutput.contains("velocity") {
            serverType = .velocity
        } else if lowerOutput.contains("vanilla") || (lowerOutput.contains("dedicated server") && !lowerOutput.contains("paper") && !lowerOutput.contains("spigot")) {
            serverType = .vanilla
        }

        return (version, serverType)
    }

    /// Tail the server log
    func tailLog(lines: Int = 100) async throws -> String {
        let logPath = "\(server.serverPath)/logs/latest.log"
        return try await execute("tail -n \(lines) '\(logPath)'")
    }

    /// Stream the server log
    func streamLog() -> AsyncStream<String> {
        let logPath = "\(server.serverPath)/logs/latest.log"
        // Use -F to follow by name (survives log rotation/recreate on restart)
        // -n 0 avoids replaying old lines when the stream is started after an initial tail load.
        return stream("tail -n 0 -F '\(logPath)'")
    }

    /// Send a command to the Minecraft server via RCON, screen, or tmux
    func sendCommand(_ command: String) async throws {
        // Try RCON first (most reliable for systemd-managed servers)
        if let rconPassword = server.rconPassword, !rconPassword.isEmpty {
            let rconHost = server.rconHost ?? "127.0.0.1"
            let rconPort = server.rconPort ?? 25575
            let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
            let escapedPassword = rconPassword.replacingOccurrences(of: "'", with: "'\\''")

            // Check if mcrcon is available, install if not
            let mcrconCheck = try? await execute("which mcrcon || which /usr/local/bin/mcrcon")
            let mcrconPath = mcrconCheck?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !mcrconPath.isEmpty {
                let rconCommand = "\(mcrconPath) -H '\(rconHost)' -P \(rconPort) -p '\(escapedPassword)' '\(escapedCommand)'"
                _ = try await execute(rconCommand)
                return
            }

            // Try to install mcrcon if not available
            _ = try? await execute("apt-get install -y mcrcon 2>/dev/null || (cd /tmp && rm -rf mcrcon && git clone https://github.com/Tiiffi/mcrcon.git && cd mcrcon && make && cp mcrcon /usr/local/bin/)")

            // Retry with mcrcon after installation
            let rconCommand = "mcrcon -H '\(rconHost)' -P \(rconPort) -p '\(escapedPassword)' '\(escapedCommand)'"
            _ = try await execute(rconCommand)
            return
        }

        // Try screen session if configured
        if let screenSession = server.screenSession, !screenSession.isEmpty {
            let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
            let screenCommand = "screen -S '\(screenSession)' -X stuff '\(escapedCommand)\n'"
            _ = try await execute(screenCommand)
            return
        }

        // Fallback: try to find a running screen session
        let screenList = try? await execute("screen -ls 2>/dev/null | awk '/[0-9]+\\./ {print $1}' | head -1")
        if let session = screenList?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
            let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
            let screenCommand = "screen -S '\(session)' -X stuff '\(escapedCommand)\n'"
            _ = try await execute(screenCommand)
            return
        }

        // Try tmux as alternative
        let tmuxList = try? await execute("tmux list-sessions 2>/dev/null | head -1 | cut -d: -f1")
        if let session = tmuxList?.trimmingCharacters(in: .whitespacesAndNewlines), !session.isEmpty {
            let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
            let tmuxCommand = "tmux send-keys -t '\(session)' '\(escapedCommand)' Enter"
            _ = try await execute(tmuxCommand)
            return
        }

        throw SSHError.commandFailed("No RCON, screen, or tmux session found. Configure RCON password or screen session in server settings.")
    }

    /// Send a command via RCON and return the response
    /// This is useful for querying server state without affecting the console
    func sendRCONCommand(_ command: String, password: String, port: Int = 25575, host: String = "127.0.0.1") async throws -> String {
        let escapedCommand = command.replacingOccurrences(of: "'", with: "'\\''")
        let escapedPassword = password.replacingOccurrences(of: "'", with: "'\\''")

        // Check if mcrcon is available
        let mcrconCheck = try? await execute("which mcrcon || which /usr/local/bin/mcrcon")
        let mcrconPath = mcrconCheck?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if mcrconPath.isEmpty {
            // Try to install mcrcon
            _ = try? await execute("apt-get install -y mcrcon 2>/dev/null || (cd /tmp && rm -rf mcrcon && git clone https://github.com/Tiiffi/mcrcon.git && cd mcrcon && make && cp mcrcon /usr/local/bin/)")
        }

        let rconCommand = "mcrcon -H '\(host)' -P \(port) -p '\(escapedPassword)' '\(escapedCommand)' 2>/dev/null"
        return try await execute(rconCommand)
    }

    /// Upload a file via scp
    func uploadFile(localPath: String, remotePath: String) async throws {
        var args: [String] = []

        // Add identity file if specified
        if let identityFile = server.identityFilePath, !identityFile.isEmpty {
            let expandedPath = NSString(string: identityFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedPath])
        }

        // SCP options
        args.append(contentsOf: [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no"
        ])

        // Port if non-standard
        if server.sshPort != 22 {
            args.append(contentsOf: ["-P", String(server.sshPort)])
        }

        // Source and destination
        args.append(localPath)
        args.append("\(server.sshUsername)@\(server.host):\(remotePath)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SSHError.commandFailed(errorOutput)
        }
    }

    /// Read file contents from remote server via SSH cat command
    func readFile(at remotePath: String) async throws -> Data {
        let output = try await execute("cat '\(remotePath)'")
        guard let data = output.data(using: String.Encoding.utf8) else {
            throw SSHError.commandFailed("Failed to read file data")
        }
        return data
    }

    /// Read file contents quickly with a shorter timeout
    /// Returns empty string if file doesn't exist (instead of throwing)
    func readFileQuick(at remotePath: String) async throws -> String {
        let logger = DebugLogger.shared
        logger.log("readFileQuick: Reading \(remotePath)", category: .ssh)

        let startTime = Date()
        do {
            // Read file directly - cat with redirection to suppress errors if file doesn't exist
            let output = try await execute("cat '\(remotePath)' 2>/dev/null || echo ''", timeout: 15)
            let elapsed = Date().timeIntervalSince(startTime)
            logger.log("readFileQuick: Completed in \(String(format: "%.2f", elapsed))s, got \(output.count) bytes", category: .ssh)
            return output
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            logger.log("readFileQuick: Failed after \(String(format: "%.2f", elapsed))s: \(error)", category: .ssh)
            // Return empty string for non-timeout errors
            if case SSHError.timeout = error {
                throw error
            }
            return ""
        }
    }

    func downloadFile(remotePath: String, localPath: String) async throws {
        var args: [String] = []

        // Add identity file if specified
        if let identityFile = server.identityFilePath, !identityFile.isEmpty {
            let expandedPath = NSString(string: identityFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedPath])
        }

        // SCP options
        args.append(contentsOf: [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no"
        ])

        // Port if non-standard
        if server.sshPort != 22 {
            args.append(contentsOf: ["-P", String(server.sshPort)])
        }

        // Source and destination
        args.append("\(server.sshUsername)@\(server.host):\(remotePath)")
        args.append(localPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SSHError.commandFailed(errorOutput)
        }
    }

    /// Download a directory recursively via scp -r
    func downloadDirectory(remotePath: String, localPath: String) async throws {
        var args: [String] = []

        // Add identity file if specified
        if let identityFile = server.identityFilePath, !identityFile.isEmpty {
            let expandedPath = NSString(string: identityFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedPath])
        }

        // SCP options with recursive flag
        args.append(contentsOf: [
            "-r",  // Recursive copy
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no"
        ])

        // Port if non-standard
        if server.sshPort != 22 {
            args.append(contentsOf: ["-P", String(server.sshPort)])
        }

        // Source and destination
        args.append("\(server.sshUsername)@\(server.host):\(remotePath)")
        args.append(localPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        process.arguments = args

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SSHError.commandFailed(errorOutput)
        }
    }

    /// Delete a file on the remote server
    func deleteFile(remotePath: String) async throws {
        _ = try await execute("rm '\(remotePath)'")
    }

    /// Delete a directory recursively on the remote server (rm -rf)
    func deleteDirectory(remotePath: String) async throws {
        _ = try await execute("rm -rf '\(remotePath)'")
    }
}
