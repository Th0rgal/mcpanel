//
//  PTYService.swift
//  MCPanel
//
//  Interactive PTY console via SSH with screen/tmux support
//  Provides real-time bidirectional I/O with full ANSI color support
//

import Foundation

// MARK: - PTY Error

enum PTYError: Error, LocalizedError {
    case connectionFailed(String)
    case sessionNotFound(String)
    case attachFailed(String)
    case notConnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "PTY connection failed: \(message)"
        case .sessionNotFound(let session):
            return "Session '\(session)' not found"
        case .attachFailed(let message):
            return "Failed to attach to session: \(message)"
        case .notConnected:
            return "Not connected to PTY"
        case .timeout:
            return "PTY operation timed out"
        }
    }
}

// MARK: - Session Type

enum SessionType: String, Codable {
    case screen
    case tmux
    case direct  // Direct PTY without multiplexer

    var displayName: String {
        switch self {
        case .screen: return "GNU Screen"
        case .tmux: return "tmux"
        case .direct: return "Direct PTY"
        }
    }
}

// MARK: - Detected Session

struct DetectedSession: Identifiable {
    let id = UUID()
    let name: String
    let type: SessionType
    let attached: Bool
    let created: Date?
}

// MARK: - PTY Service

actor PTYService {
    private let server: Server
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var isConnected = false
    private var sessionType: SessionType = .direct
    private var sessionName: String?

    // Terminal dimensions
    private var termWidth: Int = 120
    private var termHeight: Int = 40

    init(server: Server) {
        self.server = server
    }

    deinit {
        // Clean up process on dealloc
        process?.terminate()
    }

    // MARK: - Session Detection

    /// Detect available screen/tmux sessions on the remote server
    func detectSessions() async throws -> [DetectedSession] {
        var sessions: [DetectedSession] = []

        // Check for screen sessions
        let screenOutput = try? await executeCommand("screen -ls 2>/dev/null || echo ''")
        if let output = screenOutput {
            sessions.append(contentsOf: parseScreenSessions(output))
        }

        // Check for tmux sessions
        let tmuxOutput = try? await executeCommand("tmux list-sessions -F '#{session_name}|#{session_created}|#{session_attached}' 2>/dev/null || echo ''")
        if let output = tmuxOutput {
            sessions.append(contentsOf: parseTmuxSessions(output))
        }

        return sessions
    }

    private func parseScreenSessions(_ output: String) -> [DetectedSession] {
        var sessions: [DetectedSession] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Match patterns like "12345.minecraft (Attached)" or "12345.minecraft (Detached)"
            let pattern = #"(\d+\.\S+)\s+\((Attached|Detached)\)"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let nameRange = Range(match.range(at: 1), in: line),
                   let stateRange = Range(match.range(at: 2), in: line) {
                    let name = String(line[nameRange])
                    let state = String(line[stateRange])
                    sessions.append(DetectedSession(
                        name: name,
                        type: .screen,
                        attached: state == "Attached",
                        created: nil
                    ))
                }
            }
        }

        return sessions
    }

    private func parseTmuxSessions(_ output: String) -> [DetectedSession] {
        var sessions: [DetectedSession] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines where !line.isEmpty {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3 else { continue }

            let name = parts[0]
            let createdTimestamp = TimeInterval(parts[1]) ?? 0
            let attached = parts[2] == "1"

            sessions.append(DetectedSession(
                name: name,
                type: .tmux,
                attached: attached,
                created: createdTimestamp > 0 ? Date(timeIntervalSince1970: createdTimestamp) : nil
            ))
        }

        return sessions
    }

    // MARK: - Connection

    /// Connect to a screen or tmux session via SSH with PTY allocation
    func connect(sessionType: SessionType, sessionName: String?) async throws {
        self.sessionType = sessionType
        self.sessionName = sessionName

        print("[PTYService] Connecting: type=\(sessionType), session=\(sessionName ?? "nil")")

        // Build the remote command based on session type
        let remoteCommand: String
        switch sessionType {
        case .screen:
            if let name = sessionName {
                // Attach to existing screen session
                remoteCommand = "screen -x '\(name)' || screen -r '\(name)'"
            } else {
                // Try to auto-detect and attach to first available session
                remoteCommand = "screen -x $(screen -ls | awk '/[0-9]+\\./ {print $1; exit}') 2>/dev/null || screen -ls"
            }
        case .tmux:
            if let name = sessionName {
                remoteCommand = "tmux attach-session -t '\(name)'"
            } else {
                remoteCommand = "tmux attach-session 2>/dev/null || tmux list-sessions"
            }
        case .direct:
            // Just allocate a PTY and drop to shell
            remoteCommand = "cd '\(server.serverPath)' && exec bash"
        }

        print("[PTYService] Remote command: \(remoteCommand)")
        try await connectWithPTY(remoteCommand: remoteCommand)
    }

    /// Connect to SSH with PTY allocation
    private func connectWithPTY(remoteCommand: String) async throws {
        // Clean up any existing connection
        disconnect()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var args: [String] = []

        // Force PTY allocation (critical for interactive sessions)
        args.append("-tt")

        // Add identity file if specified
        if let identityFile = server.identityFilePath, !identityFile.isEmpty {
            let expandedPath = NSString(string: identityFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedPath])
        }

        // SSH options for interactive use
        args.append(contentsOf: [
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "SendEnv=TERM"  // Send TERM env var to remote
        ])

        // Port if non-standard
        if server.sshPort != 22 {
            args.append(contentsOf: ["-p", String(server.sshPort)])
        }

        // User@host
        args.append("\(server.sshUsername)@\(server.host)")

        // The remote command - wrap with TERM setting for screen compatibility
        let wrappedCommand = "TERM=xterm-256color \(remoteCommand)"
        args.append(wrappedCommand)

        process.arguments = args

        // Set up pipes for I/O
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe  // Combine stderr with stdout

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe

        do {
            try process.run()
            isConnected = true
        } catch {
            throw PTYError.connectionFailed(error.localizedDescription)
        }
    }

    /// Disconnect from the PTY session
    func disconnect() {
        isConnected = false

        // Send exit command gracefully first
        if let inputHandle = inputPipe?.fileHandleForWriting {
            // Send Ctrl+A, d for screen (detach)
            // Or just send exit
            if let exitData = "exit\n".data(using: .utf8) {
                try? inputHandle.write(contentsOf: exitData)
            }
        }

        // Give it a moment to exit cleanly
        Thread.sleep(forTimeInterval: 0.1)

        // Terminate if still running
        if process?.isRunning == true {
            process?.terminate()
        }

        // Clean up
        inputPipe?.fileHandleForWriting.closeFile()
        outputPipe?.fileHandleForReading.closeFile()
        process = nil
        inputPipe = nil
        outputPipe = nil
    }

    // MARK: - I/O Operations

    /// Send input to the PTY (commands, keystrokes, etc.)
    func send(_ text: String) async throws {
        guard isConnected, let inputHandle = inputPipe?.fileHandleForWriting else {
            throw PTYError.notConnected
        }

        guard let data = text.data(using: .utf8) else { return }

        try inputHandle.write(contentsOf: data)
    }

    /// Send a command followed by Enter
    func sendCommand(_ command: String) async throws {
        try await send(command + "\n")
    }

    /// Send a control character (e.g., Ctrl+C = 0x03)
    func sendControl(_ char: Character) async throws {
        guard let asciiValue = char.asciiValue else { return }
        let controlValue = asciiValue & 0x1F  // Convert to control character
        let data = Data([controlValue])

        guard isConnected, let inputHandle = inputPipe?.fileHandleForWriting else {
            throw PTYError.notConnected
        }

        try inputHandle.write(contentsOf: data)
    }

    /// Send special key sequence (for screen/tmux navigation)
    func sendSpecialKey(_ key: SpecialKey) async throws {
        let sequence: String
        switch key {
        case .up: sequence = "\u{1B}[A"
        case .down: sequence = "\u{1B}[B"
        case .right: sequence = "\u{1B}[C"
        case .left: sequence = "\u{1B}[D"
        case .home: sequence = "\u{1B}[H"
        case .end: sequence = "\u{1B}[F"
        case .pageUp: sequence = "\u{1B}[5~"
        case .pageDown: sequence = "\u{1B}[6~"
        case .tab: sequence = "\t"
        case .escape: sequence = "\u{1B}"
        case .backspace: sequence = "\u{7F}"
        case .delete: sequence = "\u{1B}[3~"
        }
        try await send(sequence)
    }

    /// Stream output from the PTY
    func streamOutput() -> AsyncStream<String> {
        AsyncStream { continuation in
            guard let outputHandle = outputPipe?.fileHandleForReading else {
                continuation.finish()
                return
            }

            outputHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    // EOF - connection closed
                    Task { await self?.markDisconnected() }
                    continuation.finish()
                    return
                }

                if let text = String(data: data, encoding: .utf8) {
                    continuation.yield(text)
                }
            }

            continuation.onTermination = { [weak outputHandle] _ in
                outputHandle?.readabilityHandler = nil
            }
        }
    }

    private func markDisconnected() {
        isConnected = false
    }

    /// Check if currently connected
    func checkConnected() -> Bool {
        return isConnected && process?.isRunning == true
    }

    // MARK: - Screen/Tmux Specific Commands

    /// Detach from screen session (Ctrl+A, d)
    func detachScreen() async throws {
        try await send("\u{01}d")  // Ctrl+A followed by d
    }

    /// Detach from tmux session (Ctrl+B, d)
    func detachTmux() async throws {
        try await send("\u{02}d")  // Ctrl+B followed by d
    }

    /// Scroll up in screen (Ctrl+A, Esc, then Page Up)
    func scrollUpScreen() async throws {
        try await send("\u{01}\u{1B}")  // Enter copy mode
        try await sendSpecialKey(.pageUp)
    }

    /// Scroll up in tmux (Ctrl+B, Page Up)
    func scrollUpTmux() async throws {
        try await send("\u{02}[")  // Enter copy mode
        try await sendSpecialKey(.pageUp)
    }

    // MARK: - Helper: Execute single command via non-PTY SSH

    private func executeCommand(_ command: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var args: [String] = []

        if let identityFile = server.identityFilePath, !identityFile.isEmpty {
            let expandedPath = NSString(string: identityFile).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedPath])
        }

        args.append(contentsOf: [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null"
        ])

        if server.sshPort != 22 {
            args.append(contentsOf: ["-p", String(server.sshPort)])
        }

        args.append("\(server.sshUsername)@\(server.host)")
        args.append(command)

        process.arguments = args

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Special Keys

enum SpecialKey {
    case up, down, left, right
    case home, end
    case pageUp, pageDown
    case tab, escape
    case backspace, delete
}
