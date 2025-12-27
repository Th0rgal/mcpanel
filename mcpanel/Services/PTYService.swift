//
//  PTYService.swift
//  MCPanel
//
//  Interactive PTY console via SSH with screen/tmux support
//  Provides real-time bidirectional I/O with full ANSI color support
//

import Foundation
import Darwin

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
    case mcwrap  // mcwrap session wrapper

    var displayName: String {
        switch self {
        case .screen: return "GNU Screen"
        case .tmux: return "tmux"
        case .direct: return "Direct PTY"
        case .mcwrap: return "mcwrap"
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
    private var masterFD: Int32?
    private var slaveFD: Int32?
    private var masterHandle: FileHandle?
    private var slaveHandle: FileHandle?
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
                // SwiftTerm does not provide scrollback while the client is in the alternate screen buffer.
                // tmux normally switches into the alternate screen via smcup/rmcup. We disable those
                // capabilities for xterm* so the terminal remains scrollable.
                remoteCommand = "tmux set-option -g -a terminal-overrides ',xterm*:smcup@:rmcup@' \\; attach-session -t '\(name)'"
            } else {
                remoteCommand = "tmux set-option -g -a terminal-overrides ',xterm*:smcup@:rmcup@' \\; attach-session 2>/dev/null || tmux list-sessions"
            }
        case .direct:
            // Just allocate a PTY and drop to shell
            remoteCommand = "cd '\(server.serverPath)' && exec bash"
        case .mcwrap:
            // mcwrap-pty provides PTY-based console with tab completion support
            // Fall back to basic mcwrap if mcwrap-pty is not available
            // Use --raw mode for clean I/O (no decoration, just pipe stdin/stdout)
            remoteCommand = "mcwrap-pty attach '\(server.serverPath)' --raw 2>/dev/null || mcwrap attach '\(server.serverPath)' --raw"
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

        // The remote command - wrap with TERM/COLORTERM settings for color support
        // tmux with proper config supports truecolor, screen typically falls back to 16-color
        let wrappedCommand = "TERM=xterm-256color COLORTERM=truecolor \(remoteCommand)"
        args.append(wrappedCommand)

        process.arguments = args

        // Allocate a local PTY so ssh sees a real TTY (enables proper window sizing + SIGWINCH)
        var master: Int32 = 0
        var slave: Int32 = 0
        if openpty(&master, &slave, nil, nil, nil) != 0 {
            throw PTYError.connectionFailed("Failed to allocate PTY")
        }

        // Apply initial window size before launching ssh so the remote PTY starts correctly sized
        applyWinsize(cols: termWidth, rows: termHeight, to: slave)

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: false)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle  // Combine stderr with stdout

        self.process = process
        self.masterFD = master
        self.slaveFD = slave
        self.masterHandle = masterHandle
        self.slaveHandle = slaveHandle

        do {
            try process.run()
            isConnected = true
            // Nudge ssh to propagate our current winsize to the remote
            signalResize()
        } catch {
            // Clean up FDs if launch fails
            masterHandle.closeFile()
            slaveHandle.closeFile()
            self.masterFD = nil
            self.slaveFD = nil
            self.masterHandle = nil
            self.slaveHandle = nil
            throw PTYError.connectionFailed(error.localizedDescription)
        }
    }

    /// Disconnect from the PTY session
    func disconnect() {
        isConnected = false

        // Terminate if still running
        if process?.isRunning == true {
            process?.terminate()
        }

        // Clean up
        masterHandle?.readabilityHandler = nil
        masterHandle?.closeFile()
        slaveHandle?.closeFile()
        process = nil
        masterFD = nil
        slaveFD = nil
        masterHandle = nil
        slaveHandle = nil
    }

    // MARK: - I/O Operations

    /// Update the PTY window size (and propagate it to the remote via ssh)
    func setTerminalSize(cols: Int, rows: Int) {
        termWidth = max(cols, 1)
        termHeight = max(rows, 1)

        guard let slaveFD else { return }
        applyWinsize(cols: termWidth, rows: termHeight, to: slaveFD)
        signalResize()
    }

    private func applyWinsize(cols: Int, rows: Int, to fd: Int32) {
        let safeCols = max(1, cols)
        let safeRows = max(1, rows)
        var ws = winsize(
            ws_row: UInt16(min(safeRows, Int(UInt16.max))),
            ws_col: UInt16(min(safeCols, Int(UInt16.max))),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(fd, TIOCSWINSZ, &ws)
    }

    private func signalResize() {
        guard let pid = process?.processIdentifier else { return }
        _ = kill(pid, SIGWINCH)
    }

    /// Send input to the PTY (commands, keystrokes, etc.)
    func send(_ text: String) async throws {
        guard isConnected, let masterHandle else {
            throw PTYError.notConnected
        }

        guard let data = text.data(using: .utf8) else { return }

        try masterHandle.write(contentsOf: data)
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

        guard isConnected, let masterHandle else {
            throw PTYError.notConnected
        }

        try masterHandle.write(contentsOf: data)
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
            guard let outputHandle = masterHandle else {
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
