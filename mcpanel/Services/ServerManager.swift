//
//  ServerManager.swift
//  MCPanel
//
//  Central state manager for all servers
//

import Foundation
import SwiftUI
import Combine

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case server(UUID)
    case addServer
}

// MARK: - Detail View Selection

enum DetailTab: String, CaseIterable, Identifiable {
    case console = "Console"
    case plugins = "Plugins"
    case files = "Files"
    case properties = "Properties"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .console: return "terminal.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .files: return "folder.fill"
        case .properties: return "doc.text.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Server Manager

@MainActor
class ServerManager: ObservableObject {
    // MARK: - Published State

    @Published var servers: [Server] = []
    @Published var selectedSidebar: SidebarSelection?
    @Published var selectedTab: DetailTab = .console
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Per-server state
    @Published var plugins: [UUID: [Plugin]] = [:]
    @Published var consoleMessages: [UUID: [ConsoleMessage]] = [:]
    @Published var files: [UUID: [FileItem]] = [:]
    @Published var currentPaths: [UUID: String] = [:]

    // Console
    @Published var commandText: String = ""
    @Published var commandHistory: [UUID: CommandHistory] = [:]

    // MARK: - Services

    private var sshServices: [UUID: SSHService] = [:]
    private var ptyServices: [UUID: PTYService] = [:]
    private var logStreamTasks: [UUID: Task<Void, Never>] = [:]
    private var ptyStreamTasks: [UUID: Task<Void, Never>] = [:]
    private let persistence = PersistenceService()
    private var statusRefreshTask: Task<Void, Never>?

    // PTY state
    @Published var ptyConnected: [UUID: Bool] = [:]
    @Published var detectedSessions: [UUID: [DetectedSession]] = [:]
    private var desiredPTYSize: [UUID: (cols: Int, rows: Int)] = [:]

    // Raw PTY output callbacks for SwiftTerm integration
    private var ptyOutputCallbacks: [UUID: (String) -> Void] = [:]

    // MARK: - Computed Properties

    var selectedServer: Server? {
        guard case .server(let id) = selectedSidebar else { return nil }
        return servers.first { $0.id == id }
    }

    var selectedServerPlugins: [Plugin] {
        guard let server = selectedServer else { return [] }
        return plugins[server.id] ?? []
    }

    var selectedServerConsole: [ConsoleMessage] {
        guard let server = selectedServer else { return [] }
        return consoleMessages[server.id] ?? []
    }

    var selectedServerFiles: [FileItem] {
        guard let server = selectedServer else { return [] }
        return files[server.id] ?? []
    }

    var currentPath: String {
        guard let server = selectedServer else { return "/" }
        return currentPaths[server.id] ?? server.serverPath
    }

    // MARK: - Initialization

    init() {
        Task {
            await loadServers()
            startAutoRefresh()
        }
    }

    deinit {
        statusRefreshTask?.cancel()
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        statusRefreshTask?.cancel()
        statusRefreshTask = Task {
            while !Task.isCancelled {
                // Wait 30 seconds between refreshes
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await refreshAllServers()
            }
        }
    }

    // MARK: - Persistence

    func loadServers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            servers = try await persistence.loadServers()

            // If no servers saved, try loading from secrets
            if servers.isEmpty {
                await loadFromSecrets()
            }

            // Select first server if available
            if let first = servers.first {
                selectedSidebar = .server(first.id)
                await refreshServerStatus(first)
            }
        } catch {
            print("Failed to load servers: \(error)")
            // Load from secrets.json as fallback
            await loadFromSecrets()
        }
    }

    private func loadFromSecrets() async {
        // Try multiple locations for .secrets.json
        var paths: [String] = []

        // 1. Inside app bundle Resources
        if let bundlePath = Bundle.main.path(forResource: ".secrets", ofType: "json") {
            paths.append(bundlePath)
        }

        // 2. Next to the app bundle
        let nextToBundle = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(".secrets.json")
        paths.append(nextToBundle.path)

        // 3. Current working directory
        paths.append(FileManager.default.currentDirectoryPath + "/.secrets.json")

        // 4. Home directory
        paths.append(NSHomeDirectory() + "/.mcpanel-secrets.json")

        print("Searching for secrets in: \(paths)")

        for path in paths {
            guard FileManager.default.fileExists(atPath: path),
                  let data = FileManager.default.contents(atPath: path) else {
                continue
            }

            do {
                let secrets = try JSONDecoder().decode(SecretsFile.self, from: data)
                for (_, serverConfig) in secrets.servers {
                        // Parse console mode from config
                    let consoleMode: ConsoleMode
                    if let modeStr = serverConfig.console?.mode {
                        consoleMode = ConsoleMode(rawValue: modeStr) ?? .logTail
                    } else if serverConfig.screen?.session != nil {
                        consoleMode = .ptyScreen
                    } else {
                        consoleMode = .logTail
                    }

                    let server = Server(
                        name: serverConfig.name ?? "Server",
                        host: serverConfig.ssh.host,
                        sshPort: serverConfig.ssh.port,
                        sshUsername: serverConfig.ssh.user,
                        identityFilePath: serverConfig.ssh.identityFile,
                        serverPath: serverConfig.paths.rootDir,
                        pluginsPath: serverConfig.paths.pluginsDir,
                        jarFileName: URL(fileURLWithPath: serverConfig.paths.jarPath ?? "server.jar").lastPathComponent,
                        rconHost: serverConfig.rcon?.host,
                        rconPort: serverConfig.rcon?.port,
                        rconPassword: serverConfig.rcon?.password,
                        screenSession: serverConfig.screen?.session,
                        tmuxSession: serverConfig.tmux?.session,
                        systemdUnit: serverConfig.systemd?.unit,
                        serverType: ServerType(rawValue: serverConfig.serverType ?? "paper") ?? .paper,
                        consoleMode: consoleMode,
                        minecraftVersion: serverConfig.minecraftVersion
                    )
                    servers.append(server)
                }

                if let first = servers.first {
                    selectedSidebar = .server(first.id)
                    await refreshServerStatus(first)
                }

                // Save loaded servers
                await saveServers()
                return
            } catch {
                print("Failed to parse secrets: \(error)")
            }
        }
    }

    func saveServers() async {
        do {
            try await persistence.saveServers(servers)
        } catch {
            print("Failed to save servers: \(error)")
        }
    }

    // MARK: - Server Management

    func addServer(_ server: Server) async {
        servers.append(server)
        selectedSidebar = .server(server.id)
        await saveServers()
        await refreshServerStatus(server)
    }

    func removeServer(_ server: Server) async {
        // Cancel any running tasks
        logStreamTasks[server.id]?.cancel()
        logStreamTasks.removeValue(forKey: server.id)
        sshServices.removeValue(forKey: server.id)

        servers.removeAll { $0.id == server.id }

        // Update selection
        if case .server(let id) = selectedSidebar, id == server.id {
            selectedSidebar = servers.first.map { .server($0.id) }
        }

        await saveServers()
    }

    func updateServer(_ server: Server) async {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            await saveServers()
        }
    }

    // MARK: - SSH Service Access

    func sshService(for server: Server) -> SSHService {
        // Always create a new service with the latest server data to ensure
        // RCON credentials and other settings are current
        let service = SSHService(server: server)
        sshServices[server.id] = service
        return service
    }

    func ptyService(for server: Server) -> PTYService {
        if let existing = ptyServices[server.id] {
            return existing
        }
        let service = PTYService(server: server)
        ptyServices[server.id] = service
        return service
    }

    // MARK: - Server Status

    func refreshServerStatus(_ server: Server) async {
        let ssh = sshService(for: server)

        do {
            let isRunning = try await ssh.isServerRunning()

            if let index = servers.firstIndex(where: { $0.id == server.id }) {
                servers[index].status = isRunning ? .online : .offline
                servers[index].lastChecked = Date()

                // Auto-detect version and server type if not set or if online
                if isRunning {
                    if let (detectedVersion, detectedType) = try? await ssh.detectServerInfo() {
                        if let version = detectedVersion {
                            servers[index].minecraftVersion = version
                        }
                        if let serverType = detectedType {
                            servers[index].serverType = serverType
                        }
                        // Save updated server info
                        await saveServers()
                    }
                }
            }
        } catch {
            if let index = servers.firstIndex(where: { $0.id == server.id }) {
                servers[index].status = .unknown
            }
            errorMessage = error.localizedDescription
        }
    }

    func refreshAllServers() async {
        for server in servers {
            await refreshServerStatus(server)
        }
    }

    // MARK: - Server Control

    func startServer(_ server: Server) async {
        let ssh = sshService(for: server)

        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].status = .starting
        }

        do {
            try await ssh.startServer()
            // Wait a bit then check status
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshServerStatus(server)
        } catch {
            errorMessage = error.localizedDescription
            await refreshServerStatus(server)
        }
    }

    func stopServer(_ server: Server) async {
        let ssh = sshService(for: server)

        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].status = .stopping
        }

        // Prefer sending stop via the live console so the user can see the shutdown happen.
        // This also avoids requiring systemctl permissions in some setups.
        if ptyConnected[server.id] == true {
            await sendPTYCommand("stop", to: server)
        } else {
            // Fall back to whichever mechanism is available (RCON/screen/tmux auto-detect).
            do {
                try await ssh.sendCommand("stop")
            } catch {
                // We'll still try the more forceful stop path below.
                print("[Stop] Failed to send stop command: \(error)")
            }
        }

        // Give the server some time to shut down gracefully.
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await refreshServerStatus(server)
            if let updated = servers.first(where: { $0.id == server.id }), updated.status == .offline {
                return
            }
        }

        do {
            try await ssh.stopServer()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshServerStatus(server)
        } catch {
            errorMessage = error.localizedDescription
            await refreshServerStatus(server)
        }
    }

    func restartServer(_ server: Server) async {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].status = .stopping
        }

        // Prefer the in-console restart command so the user sees it, and it works even without systemctl.
        // (Paper/Spigot commonly support a `restart` console command via restart scripts.)
        if ptyConnected[server.id] == true {
            await sendPTYCommand("restart", to: server)
        } else {
            let ssh = sshService(for: server)
            do {
                try await ssh.sendCommand("restart")
            } catch {
                // Fall back to systemd restart if configured
                do {
                    try await ssh.restartServer()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }

        // Reflect that we're restarting and refresh status a bit later.
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].status = .starting
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await refreshServerStatus(server)
    }

    // MARK: - Console

    func loadConsole(for server: Server) async {
        let ssh = sshService(for: server)

        do {
            let logOutput = try await ssh.tailLog(lines: 200)
            let lines = logOutput.components(separatedBy: .newlines)
            let messages = lines.map { ConsoleMessage.parse($0) }
            consoleMessages[server.id] = messages
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startLogStream(for server: Server) {
        // Cancel existing stream
        logStreamTasks[server.id]?.cancel()

        let ssh = sshService(for: server)
        let serverId = server.id

        logStreamTasks[server.id] = Task {
            let stream = await ssh.streamLog()
            for await line in stream {
                guard !Task.isCancelled else { break }
                let message = ConsoleMessage.parse(line)
                await MainActor.run {
                    var messages = self.consoleMessages[serverId] ?? []
                    messages.append(message)
                    // Keep last 1000 messages
                    if messages.count > 1000 {
                        messages.removeFirst(messages.count - 1000)
                    }
                    self.consoleMessages[serverId] = messages
                }
            }
        }
    }

    func stopLogStream(for server: Server) {
        logStreamTasks[server.id]?.cancel()
        logStreamTasks.removeValue(forKey: server.id)
    }

    func sendCommand(_ command: String, to server: Server) async {
        guard !command.isEmpty else { return }

        // Add to history
        var history = commandHistory[server.id] ?? CommandHistory()
        history.add(command)
        commandHistory[server.id] = history

        // Don't add command to console - let the server echo it back via PTY
        // This avoids duplicate display and keeps the UI consistent with server behavior

        // Send via PTY if connected, otherwise via SSH
        if ptyConnected[server.id] == true {
            await sendPTYCommand(command, to: server)
        } else {
            // Send command via SSH
            let ssh = sshService(for: server)
            do {
                try await ssh.sendCommand(command)
            } catch {
                // Add error message to console
                let errorMessage = ConsoleMessage(
                    level: .error,
                    content: "Failed to send command: \(error.localizedDescription)"
                )
                consoleMessages[server.id]?.append(errorMessage)
            }
        }
    }

    // MARK: - PTY Console

    /// Detect available screen/tmux sessions on the server
    func detectPTYSessions(for server: Server) async {
        let pty = ptyService(for: server)
        do {
            let sessions = try await pty.detectSessions()
            detectedSessions[server.id] = sessions
        } catch {
            errorMessage = "Failed to detect sessions: \(error.localizedDescription)"
        }
    }

    /// Connect to PTY console (screen/tmux session)
    func connectPTY(for server: Server, sessionName: String? = nil) async {
        // Use the server's configured console mode
        guard let sessionType = server.consoleMode.sessionType else {
            // Fall back to log tail mode
            print("[PTY] Console mode is logTail, falling back to log stream")
            await loadConsole(for: server)
            return
        }

        print("[PTY] Connecting with mode: \(server.consoleMode), sessionType: \(sessionType)")

        // Disconnect any existing PTY
        await disconnectPTY(for: server)

        // Create new PTY service
        let pty = PTYService(server: server)
        ptyServices[server.id] = pty

        // Determine session name
        let targetSession: String?
        switch server.consoleMode {
        case .ptyScreen:
            targetSession = sessionName ?? server.screenSession
            print("[PTY] Screen session target: \(targetSession ?? "auto-detect")")
        case .ptyTmux:
            targetSession = sessionName ?? server.tmuxSession
            print("[PTY] Tmux session target: \(targetSession ?? "auto-detect")")
        default:
            targetSession = sessionName
        }

        do {
            try await pty.connect(sessionType: sessionType, sessionName: targetSession)
            ptyConnected[server.id] = true
            print("[PTY] Connected successfully")

            // Apply any pending terminal size that the UI has reported.
            if let desired = desiredPTYSize[server.id] {
                await pty.setTerminalSize(cols: desired.cols, rows: desired.rows)
            }

            // Start streaming PTY output
            startPTYStream(for: server)

            // Add info message
            let infoMessage = ConsoleMessage(
                level: .info,
                content: "Connected to \(server.consoleMode.rawValue) console"
            )
            var messages = consoleMessages[server.id] ?? []
            messages.append(infoMessage)
            consoleMessages[server.id] = messages
        } catch {
            ptyConnected[server.id] = false
            errorMessage = "PTY connection failed: \(error.localizedDescription)"

            let errorMsg = ConsoleMessage(
                level: .error,
                content: "Failed to connect: \(error.localizedDescription)"
            )
            var messages = consoleMessages[server.id] ?? []
            messages.append(errorMsg)
            consoleMessages[server.id] = messages
        }
    }

    /// Disconnect from PTY console
    func disconnectPTY(for server: Server) async {
        // Cancel stream task
        ptyStreamTasks[server.id]?.cancel()
        ptyStreamTasks.removeValue(forKey: server.id)

        // Disconnect PTY
        if let pty = ptyServices[server.id] {
            await pty.disconnect()
        }
        ptyServices.removeValue(forKey: server.id)
        ptyConnected[server.id] = false
    }

    /// Start streaming PTY output
    private func startPTYStream(for server: Server) {
        // Cancel existing stream
        ptyStreamTasks[server.id]?.cancel()

        guard let pty = ptyServices[server.id] else { return }

        let serverId = server.id

        ptyStreamTasks[server.id] = Task {
            let stream = await pty.streamOutput()
            for await chunk in stream {
                guard !Task.isCancelled else { break }

                // Send raw output to SwiftTerm callback if registered
                await MainActor.run {
                    if let callback = self.ptyOutputCallbacks[serverId] {
                        callback(chunk)
                    }
                }

                // Also process for legacy console messages (can be removed once SwiftTerm is fully integrated)
                await MainActor.run {
                    // Split by newlines but preserve the raw output for ANSI parsing
                    let lines = chunk.components(separatedBy: "\n")
                    for (index, line) in lines.enumerated() {
                        // Skip empty lines except the last one (might be partial)
                        if line.isEmpty && index < lines.count - 1 { continue }
                        if line.isEmpty { continue }

                        // Skip tmux status lines (e.g., "[session:window*    "hostname" HH:MM DD-Mon-YY")
                        if self.isTmuxStatusLine(line) { continue }

                        // Filter out server prompt lines and command echoes
                        if self.shouldFilterLine(line) { continue }

                        // Create message - PTY output should be treated as raw with ANSI codes
                        let message = ConsoleMessage(
                            level: .info,
                            content: line,
                            rawANSI: true  // Mark as raw ANSI for proper parsing
                        )

                        var messages = self.consoleMessages[serverId] ?? []
                        messages.append(message)

                        // Keep last 1000 messages
                        if messages.count > 1000 {
                            messages.removeFirst(messages.count - 1000)
                        }
                        self.consoleMessages[serverId] = messages
                    }
                }
            }

            // Stream ended - mark as disconnected
            await MainActor.run {
                self.ptyConnected[serverId] = false
            }
        }
    }

    /// Register a callback to receive raw PTY output (for SwiftTerm)
    func registerPTYOutputCallback(for server: Server, callback: @escaping (String) -> Void) {
        ptyOutputCallbacks[server.id] = callback
    }

    /// Unregister PTY output callback
    func unregisterPTYOutputCallback(for server: Server) {
        ptyOutputCallbacks.removeValue(forKey: server.id)
    }

    /// Check if a line should be filtered (standalone prompts only)
    private func shouldFilterLine(_ line: String) -> Bool {
        // Strip ANSI escape sequences for pattern matching
        let stripped = line.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[^\\[\\]][A-Za-z]",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        // Filter standalone prompt lines (just ">") - these are redundant with our UI prompt
        if stripped == ">" || stripped == "> " {
            return true
        }

        return false
    }

    /// Send command via PTY
    func sendPTYCommand(_ command: String, to server: Server) async {
        guard let pty = ptyServices[server.id] else {
            errorMessage = "Not connected to PTY"
            return
        }

        do {
            try await pty.sendCommand(command)
        } catch {
            let errorMsg = ConsoleMessage(
                level: .error,
                content: "Failed to send command: \(error.localizedDescription)"
            )
            var messages = consoleMessages[server.id] ?? []
            messages.append(errorMsg)
            consoleMessages[server.id] = messages
        }
    }

    /// Send raw text to PTY (for tab completion, partial input, etc.)
    func sendPTYRaw(_ text: String, to server: Server) async {
        guard let pty = ptyServices[server.id] else { return }
        try? await pty.send(text)
    }

    /// Resize the active PTY session to match the on-screen terminal size.
    /// This updates the local PTY winsize and triggers ssh to propagate the change to the remote.
    func resizePTY(for server: Server, cols: Int, rows: Int) async {
        desiredPTYSize[server.id] = (cols: cols, rows: rows)
        guard let pty = ptyServices[server.id] else { return }
        await pty.setTerminalSize(cols: cols, rows: rows)
    }

    /// Send a special key to PTY (arrow keys, etc.)
    func sendPTYKey(_ key: SpecialKey, to server: Server) async {
        guard let pty = ptyServices[server.id] else { return }
        try? await pty.sendSpecialKey(key)
    }

    /// Send control character to PTY (Ctrl+C, etc.)
    func sendPTYControl(_ char: Character, to server: Server) async {
        guard let pty = ptyServices[server.id] else { return }
        try? await pty.sendControl(char)
    }

    /// Check if PTY is connected for a server
    func isPTYConnected(for server: Server) -> Bool {
        return ptyConnected[server.id] == true
    }

    /// Check if a line is a tmux status line that should be filtered out
    /// Matches patterns like: [session:window*           "hostname" 17:46 26-Dec-25
    private func isTmuxStatusLine(_ line: String) -> Bool {
        // Strip ANSI escape sequences for pattern matching
        let stripped = line.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[A-Za-z]|\\x1B\\][^\\x07]*\\x07|\\x1B[^\\[\\]][A-Za-z]",
            with: "",
            options: .regularExpression
        )

        // Tmux status line pattern: [session:window* or [session:window-
        // followed by spaces, quotes, hostname, time, and date
        let tmuxStatusPattern = #"^\[[\w\d-]+:[\w\d*-]+\s+"#
        if let regex = try? NSRegularExpression(pattern: tmuxStatusPattern),
           regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) != nil {
            return true
        }

        // Also filter tmux window list lines
        // Pattern: (N) session:window* or (N) session:window-
        let tmuxWindowListPattern = #"^\(\d+\)\s+[\w\d-]+:[\w\d*-]+\s+"#
        if let regex = try? NSRegularExpression(pattern: tmuxWindowListPattern),
           regex.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) != nil {
            return true
        }

        return false
    }

    // MARK: - Plugins

    func loadPlugins(for server: Server) async {
        let ssh = sshService(for: server)

        do {
            let pluginList = try await ssh.listPlugins()
            plugins[server.id] = pluginList
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePlugin(_ plugin: Plugin, for server: Server) async {
        let ssh = sshService(for: server)

        do {
            try await ssh.togglePlugin(plugin)
            // Reload plugins
            await loadPlugins(for: server)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Files

    func loadFiles(for server: Server, path: String? = nil) async {
        let ssh = sshService(for: server)
        let targetPath = path ?? server.serverPath

        currentPaths[server.id] = targetPath

        do {
            let fileList = try await ssh.listFiles(path: targetPath)
            files[server.id] = fileList.sorted { file1, file2 in
                // Directories first, then alphabetically
                if file1.isDirectory != file2.isDirectory {
                    return file1.isDirectory
                }
                return file1.name.lowercased() < file2.name.lowercased()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func navigateToPath(_ path: String, for server: Server) async {
        await loadFiles(for: server, path: path)
    }

    func navigateUp(for server: Server) async {
        let current = currentPaths[server.id] ?? server.serverPath
        let parent = (current as NSString).deletingLastPathComponent
        await loadFiles(for: server, path: parent)
    }
}

// MARK: - Secrets File Model

private struct SecretsFile: Codable {
    let servers: [String: ServerConfig]

    struct ServerConfig: Codable {
        let name: String?
        let ssh: SSHConfig
        let paths: PathsConfig
        let rcon: RCONConfig?
        let screen: ScreenConfig?
        let tmux: TmuxConfig?
        let console: ConsoleConfig?
        let systemd: SystemdConfig?
        let serverType: String?
        let minecraftVersion: String?

        enum CodingKeys: String, CodingKey {
            case name, ssh, paths, rcon, screen, tmux, console, systemd
            case serverType = "server_type"
            case minecraftVersion = "minecraft_version"
        }
    }

    struct ScreenConfig: Codable {
        let session: String?
    }

    struct TmuxConfig: Codable {
        let session: String?
    }

    struct ConsoleConfig: Codable {
        let mode: String?  // "Log Tail", "Screen", "Tmux", "Direct"
    }

    struct SSHConfig: Codable {
        let host: String
        let port: Int
        let user: String
        let identityFile: String?

        enum CodingKeys: String, CodingKey {
            case host, port, user
            case identityFile = "identity_file"
        }
    }

    struct PathsConfig: Codable {
        let rootDir: String
        let pluginsDir: String?
        let jarPath: String?

        enum CodingKeys: String, CodingKey {
            case rootDir = "root_dir"
            case pluginsDir = "plugins_dir"
            case jarPath = "jar_path"
        }
    }

    struct RCONConfig: Codable {
        let host: String?
        let port: Int?
        let password: String?
    }

    struct SystemdConfig: Codable {
        let unit: String?
    }
}
