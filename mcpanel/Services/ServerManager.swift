//
//  ServerManager.swift
//  MCPanel
//
//  Central state manager for all servers
//

import Foundation
import SwiftUI
import Combine

// MARK: - Brigadier Command Tree

/// Hierarchical command structure parsed from Brigadier JSON
struct BrigadierCommandTree {
    /// Root commands available on this server
    var rootCommands: Set<String> = []

    /// Subcommands for each root command (e.g., "oraxen" -> ["reload", "give", "pack", ...])
    var subcommands: [String: Set<String>] = [:]

    /// Get all known commands (flat list)
    var allCommands: [String] {
        return rootCommands.sorted()
    }

    /// Check if a command has subcommands
    func hasSubcommands(_ command: String) -> Bool {
        return !(subcommands[command.lowercased()]?.isEmpty ?? true)
    }

    /// Get subcommands for a root command
    func getSubcommands(for command: String) -> [String] {
        return subcommands[command.lowercased()]?.sorted() ?? []
    }
}

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case server(UUID)
    case addServer
}

// MARK: - Detail View Selection

enum DetailTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case console = "Console"
    case plugins = "Plugins"
    case files = "Files"
    case properties = "Properties"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.bottom.50percent"
        case .console: return "terminal.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .files: return "folder.fill"
        case .properties: return "doc.text.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - PTY Consumers

enum PTYConsumer: String, Hashable {
    case console
    case dashboard
}

// MARK: - Server Manager

@MainActor
class ServerManager: ObservableObject {
    // MARK: - Published State

    @Published var servers: [Server] = []
    @Published var selectedSidebar: SidebarSelection?
    @Published var selectedTab: DetailTab = .dashboard
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
    private var ptyDisconnectTasks: [UUID: Task<Void, Never>] = [:]
    private var restartWatchdogTasks: [UUID: Task<Void, Never>] = [:]
    private let persistence = PersistenceService()
    private var statusRefreshTask: Task<Void, Never>?

    // PTY state
    @Published var ptyConnected: [UUID: Bool] = [:]
    @Published var detectedSessions: [UUID: [DetectedSession]] = [:]
    private var desiredPTYSize: [UUID: (cols: Int, rows: Int)] = [:]
    private var serverRestarting: [UUID: Bool] = [:]  // Track if server is in restart process
    private var lastPTYOutputAt: [UUID: Date] = [:]
    private var restartRequestedAt: [UUID: Date] = [:]
    private var lastPTYOutputWasNotRunning: [UUID: Bool] = [:]
    private var ptyConsumers: [UUID: Set<PTYConsumer>] = [:]
    private let ptyDisconnectGraceSeconds: TimeInterval = 10

    // Raw PTY output callbacks for SwiftTerm integration
    private var ptyOutputCallbacks: [UUID: (String) -> Void] = [:]

    // Brigadier command tree (discovered from server's commands.json)
    @Published var commandTree: [UUID: BrigadierCommandTree] = [:]
    private var commandDiscoveryTask: [UUID: Task<Void, Never>] = [:]

    // MCPanel Bridge services (one per server)
    @Published var bridgeServices: [UUID: MCPanelBridgeService] = [:]
    private var bridgeCommandTreeSubscriptions: [UUID: AnyCancellable] = [:]
    private var bridgeCommandTreeRefreshTasks: [UUID: Task<Void, Never>] = [:]

    /// Counter that increments when command trees are updated - views can observe this
    @Published var commandTreeUpdateCount = 0

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

            // Select first server if available and load its data
            if let first = servers.first {
                selectedSidebar = .server(first.id)
                await refreshServerStatus(first)
                await loadConsole(for: first)
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
                    await loadConsole(for: first)
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

    /// Get or create bridge service for a server
    func bridgeService(for server: Server) -> MCPanelBridgeService {
        if let existing = bridgeServices[server.id] {
            // Update configuration in case server settings changed
            existing.configure(server: server, sshService: sshService(for: server))
            ensureBridgeCommandTreeSubscription(for: server.id, service: existing)
            return existing
        }
        let service = MCPanelBridgeService()
        service.configure(server: server, sshService: sshService(for: server))
        bridgeServices[server.id] = service
        ensureBridgeCommandTreeSubscription(for: server.id, service: service)
        return service
    }

    /// Keep `commandTree` (used by the UI suggestions) in sync with bridge `commands.json` updates.
    /// Without this, the bridge may have the full tree (including plugin commands) but the UI won't refresh
    /// because it doesn't observe the bridge service object directly.
    private func ensureBridgeCommandTreeSubscription(for serverId: UUID, service: MCPanelBridgeService) {
        if bridgeCommandTreeSubscriptions[serverId] != nil {
            DebugLogger.shared.log("ensureBridgeCommandTreeSubscription: subscription already exists for \(serverId)", category: .commands, verbose: true)
            return
        }

        DebugLogger.shared.log("ensureBridgeCommandTreeSubscription: creating new subscription for \(serverId)", category: .commands)

        bridgeCommandTreeSubscriptions[serverId] = service.$commandTree
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                guard let self else { return }
                guard let payload else {
                    DebugLogger.shared.log("Combine subscription: payload is nil", category: .commands, verbose: true)
                    return
                }

                var tree = BrigadierCommandTree()
                tree.rootCommands = Set(payload.commands.keys)
                for (name, node) in payload.commands {
                    if let children = node.children {
                        tree.subcommands[name.lowercased()] = Set(children.keys)
                    }
                }

                let oCommands = tree.rootCommands.filter { $0.lowercased().hasPrefix("o") }
                DebugLogger.shared.log("Combine subscription: received \(payload.commands.count) commands, 'o' commands: \(oCommands.sorted()), setting tree for \(serverId)", category: .commands)

                self.commandTree[serverId] = tree
                self.commandTreeUpdateCount += 1
                DebugLogger.shared.log("Combine subscription: commandTreeUpdateCount is now \(self.commandTreeUpdateCount)", category: .commands)
            }
    }

    /// In mcwrap mode, the bridge plugin may generate `commands.json` *after* MCPanel connects.
    /// If our initial fetch happens too early (file missing), we never learn plugin commands like `oraxen`.
    /// We therefore listen for the bridge log line ("Generated command dump") and re-fetch (debounced).
    private func scheduleBridgeCommandTreeRefresh(for serverId: UUID, reason: String) {
        guard let server = servers.first(where: { $0.id == serverId }) else { return }

        bridgeCommandTreeRefreshTasks[serverId]?.cancel()
        bridgeCommandTreeRefreshTasks[serverId] = Task { [weak self] in
            // Debounce bursts (bridge may log twice on startup / reload)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self, !Task.isCancelled else { return }

            let bridge = self.bridgeService(for: server)
            print("[Bridge] Refreshing commands.json via SFTP (reason=\(reason))")
            await bridge.fetchCommandTree()
            // `commandTreeUpdateCount` is incremented by the Combine subscription in `ensureBridgeCommandTreeSubscription`.
        }
    }

    private func lineIndicatesBridgeCommandDump(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("generated command dump")
            || (lower.contains("bridge ready") && lower.contains("features:"))
    }

    private func stripANSIAndTrim(_ line: String) -> String {
        return line.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*[A-Za-z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[^\\[\\]][A-Za-z]",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    private func lineIndicatesServerNotRunning(_ line: String) -> Bool {
        let stripped = stripANSIAndTrim(line)
        let lower = stripped.lowercased()
        return lower == "not running" || lower.contains("server is not running")
    }

    /// Check if bridge is detected for a server
    func isBridgeDetected(for server: Server) -> Bool {
        return bridgeServices[server.id]?.bridgeDetected ?? false
    }

    /// Set dashboard active state (for high-frequency updates)
    /// When active, requests 500ms update interval from the bridge
    func setDashboardActive(_ active: Bool, for serverId: UUID) {
        guard let bridge = bridgeServices[serverId] else { return }
        bridge.dashboardActive = active

        // TODO: Send set_update_interval request to bridge plugin
        // For now, the bridge sends updates at a fixed rate, but we could
        // add a protocol message to request higher frequency when dashboard is visible:
        // sendBridgeRequest(SetUpdateIntervalRequest(intervalMs: active ? 500 : 10000))
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

    private enum ServerControlAction {
        case stop
        case restart
    }

    private func normalizedCommand(_ command: String) -> String {
        command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func availableRootCommands(for server: Server) -> Set<String> {
        var commands = Set<String>()

        if let tree = commandTree[server.id] {
            commands.formUnion(tree.rootCommands.map { $0.lowercased() })
        }

        if let bridgeTree = bridgeServices[server.id]?.commandTree {
            commands.formUnion(bridgeTree.commands.keys.map { $0.lowercased() })
        }

        return commands
    }

    private func controlCommandCandidates(for server: Server, action: ServerControlAction) -> [String] {
        switch action {
        case .stop:
            if server.serverType == .velocity {
                return ["end", "shutdown", "stop"]
            }
            return ["stop", "end", "shutdown"]
        case .restart:
            if server.serverType == .velocity {
                return ["end", "shutdown", "restart", "stop"]
            }
            return ["restart", "stop"]
        }
    }

    private func resolveControlCommand(for server: Server, action: ServerControlAction) -> String {
        let candidates = controlCommandCandidates(for: server, action: action)
        let available = availableRootCommands(for: server)

        if !available.isEmpty {
            for candidate in candidates where available.contains(candidate.lowercased()) {
                return candidate
            }
        }

        return candidates.first ?? "stop"
    }

    private func isStopCommand(_ command: String, for server: Server) -> Bool {
        let normalized = normalizedCommand(command)
        if server.serverType == .velocity {
            return normalized == "stop" || normalized == "end" || normalized == "shutdown"
        }
        return normalized == "stop"
    }

    private func isRestartCommand(_ command: String) -> Bool {
        let normalized = normalizedCommand(command)
        return normalized == "restart" || normalized == "rl"
    }

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

        serverRestarting[server.id] = false
        restartRequestedAt.removeValue(forKey: server.id)
        stopRestartWatchdog(for: server.id)

        let stopCommand = resolveControlCommand(for: server, action: .stop)

        // Prefer sending stop via the live console so the user can see the shutdown happen.
        // This also avoids requiring systemctl permissions in some setups.
        if ptyConnected[server.id] == true {
            await sendPTYCommand(stopCommand, to: server)
        } else {
            // Fall back to whichever mechanism is available (RCON/screen/tmux auto-detect).
            if server.systemdUnit != nil {
                do {
                    try await ssh.stopServer()
                } catch {
                    // We'll still try the more forceful stop path below.
                    print("[Stop] Failed to stop via systemd: \(error)")
                }
            } else {
                do {
                    try await ssh.sendCommand(stopCommand)
                } catch {
                    // We'll still try the more forceful stop path below.
                    print("[Stop] Failed to send stop command: \(error)")
                }
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
            if server.systemdUnit != nil {
                try await ssh.stopServer()
            }
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

        // Mark server as restarting so PTY can auto-reconnect (PTY modes only)
        let shouldReconnectConsole = server.consoleMode != .logTail
        serverRestarting[server.id] = shouldReconnectConsole
        restartRequestedAt[server.id] = Date()
        if shouldReconnectConsole {
            startRestartWatchdog(for: server)
        }

        // Restart strategy:
        // - If systemd is configured, prefer `systemctl restart` (reliable; doesn't depend on Paper restart scripts).
        // - Otherwise, fall back to in-console `restart` command.
        let ssh = sshService(for: server)
        let restartCommand = resolveControlCommand(for: server, action: .restart)
        if server.systemdUnit != nil {
            do {
                try await ssh.restartServer()
            } catch {
                errorMessage = error.localizedDescription
            }
        } else if ptyConnected[server.id] == true {
            await sendPTYCommand(restartCommand, to: server)
        } else {
            do {
                try await ssh.sendCommand(restartCommand)
            } catch {
                errorMessage = error.localizedDescription
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

        // Detect restart/stop commands to enable auto-reconnection
        let lowercaseCommand = normalizedCommand(command)
        if isRestartCommand(lowercaseCommand) {
            serverRestarting[server.id] = true
            restartRequestedAt[server.id] = Date()
            print("[PTY] Detected restart command, enabling auto-reconnect")
            if server.consoleMode != .logTail {
                startRestartWatchdog(for: server)
            }
        } else if isStopCommand(lowercaseCommand, for: server) {
            // For stop, we don't auto-reconnect - user needs to start manually
            serverRestarting[server.id] = false
            restartRequestedAt.removeValue(forKey: server.id)
            stopRestartWatchdog(for: server.id)
        }

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

    /// Acquire a PTY connection for a UI consumer (console/dashboard).
    /// Keeps the connection alive while at least one consumer is active.
    func acquirePTY(for server: Server, consumer: PTYConsumer) async {
        let serverId = server.id
        var consumers = ptyConsumers[serverId] ?? []
        consumers.insert(consumer)
        ptyConsumers[serverId] = consumers
        cancelPendingPTYDisconnect(for: serverId)

        // Log tail mode doesn't use PTY; just refresh console output.
        if server.consoleMode == .logTail {
            await loadConsole(for: server)
            return
        }

        // Only connect if we aren't already connected.
        if ptyConnected[serverId] != true || ptyServices[serverId] == nil {
            await connectPTY(for: server)
        }
    }

    /// Release a PTY consumer and schedule a disconnect if no one else is using it.
    func releasePTY(for server: Server, consumer: PTYConsumer, delaySeconds: TimeInterval? = nil) {
        let serverId = server.id
        var consumers = ptyConsumers[serverId] ?? []
        consumers.remove(consumer)
        ptyConsumers[serverId] = consumers

        guard consumers.isEmpty else { return }

        let delay = delaySeconds ?? ptyDisconnectGraceSeconds
        schedulePTYDisconnect(for: server, delaySeconds: delay)
    }

    private func schedulePTYDisconnect(for server: Server, delaySeconds: TimeInterval) {
        let serverId = server.id
        cancelPendingPTYDisconnect(for: serverId)

        ptyDisconnectTasks[serverId] = Task { [weak self] in
            let clampedDelay = max(0, delaySeconds)
            if clampedDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(clampedDelay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }

            // Only disconnect if no consumers re-acquired the PTY.
            let consumers = self.ptyConsumers[serverId] ?? []
            guard consumers.isEmpty else { return }

            await self.disconnectPTY(for: server)
        }
    }

    private func cancelPendingPTYDisconnect(for serverId: UUID) {
        ptyDisconnectTasks[serverId]?.cancel()
        ptyDisconnectTasks.removeValue(forKey: serverId)
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

            // For mcwrap mode, hydrate the console from scrollback first so we don't miss startup logs
            // during reconnects/restarts.
            if server.consoleMode == .ptyMcwrap {
                await hydrateConsoleFromMcwrapScrollback(for: server)
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

    /// Hydrate/patch the visible console using `mcwrap-pty log` so we don't miss logs during reconnects.
    /// This merges scrollback with the existing in-memory console when possible, otherwise replaces it.
    private func hydrateConsoleFromMcwrapScrollback(for server: Server) async {
        guard server.consoleMode == .ptyMcwrap else { return }
        guard let scrollback = await fetchScrollbackHistory(for: server) else { return }

        let lines = scrollback.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }

        let serverId = server.id

        // Helper to strip ANSI for matching
        func stripANSI(_ s: String) -> String {
            s.replacingOccurrences(
                of: "\u{1B}\\[[0-9;]*[A-Za-z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[^\\[\\]][A-Za-z]",
                with: "",
                options: .regularExpression
            )
        }

        let fetchedStripped = lines.map(stripANSI)
        let existing = consoleMessages[serverId] ?? []
        let existingTail = Array(existing.suffix(50))

        // Find best match: last existing line that appears in fetched scrollback.
        var matchIndexInFetched: Int?
        for msg in existingTail.reversed() {
            let needleRaw = msg.content
            let needleStripped = stripANSI(needleRaw)
            if let idx = fetchedStripped.lastIndex(where: { $0 == needleStripped || $0 == needleRaw }) {
                matchIndexInFetched = idx
                break
            }
        }

        let newMessages: [ConsoleMessage]
        if let idx = matchIndexInFetched, idx + 1 < lines.count {
            // Append only the new portion.
            let appendLines = lines[(idx + 1)...]
            var merged = existing
            for line in appendLines {
                merged.append(ConsoleMessage(level: .info, content: line, rawANSI: true))
            }
            if merged.count > 1000 {
                merged.removeFirst(merged.count - 1000)
            }
            newMessages = merged
        } else {
            // Replace with last portion of scrollback (more reliable than guessing)
            let trimmed = lines.suffix(800)
            newMessages = trimmed.map { ConsoleMessage(level: .info, content: $0, rawANSI: true) }
        }

        consoleMessages[serverId] = newMessages
    }

    /// Disconnect from PTY console
    func disconnectPTY(for server: Server) async {
        // Cancel any pending delayed disconnect for this server
        cancelPendingPTYDisconnect(for: server.id)

        // Cancel stream task
        ptyStreamTasks[server.id]?.cancel()
        ptyStreamTasks.removeValue(forKey: server.id)
        // If we're in the middle of a restart, the watchdog may be the thing
        // driving reconnection. Don't cancel it here.
        if serverRestarting[server.id] != true {
            stopRestartWatchdog(for: server.id)
        }

        // Disconnect PTY
        if let pty = ptyServices[server.id] {
            await pty.disconnect()
        }
        ptyServices.removeValue(forKey: server.id)
        ptyConnected[server.id] = false

        // Reset bridge service
        bridgeServices[server.id]?.reset()
    }

    /// Fetch scrollback history from tmux/mcwrap session
    /// Returns the scrollback content that can be fed to a terminal
    func fetchScrollbackHistory(for server: Server) async -> String? {
        let ssh = sshService(for: server)

        do {
            switch server.consoleMode {
            case .ptyTmux:
                // Get tmux session name
                let sessionName = server.tmuxSession ?? "minecraft"
                // Capture full scrollback history from tmux (-S - means from start of scrollback)
                // -p prints to stdout, -e includes escape sequences for colors
                let scrollback = try await ssh.execute("tmux capture-pane -t '\(sessionName)' -p -S - -e 2>/dev/null || echo ''")
                if !scrollback.isEmpty {
                    print("[Scrollback] Fetched \(scrollback.count) bytes from tmux session '\(sessionName)'")
                    return scrollback
                }
            case .ptyMcwrap:
                // Use mcwrap-pty's log command to get console history (falls back to mcwrap)
                // This outputs the scrollback buffer with ANSI colors preserved
                // Use a larger window to reliably cover startup after restart/reconnect.
                let scrollback = try await ssh.execute("mcwrap-pty log '\(server.serverPath)' 2000 2>/dev/null || mcwrap log '\(server.serverPath)' 2000 2>/dev/null || echo ''")
                if !scrollback.isEmpty && scrollback != "\n" {
                    print("[Scrollback] Fetched \(scrollback.count) bytes from mcwrap log")
                    return scrollback
                }
            case .logTail:
                // For log tail mode, load from latest.log
                let logOutput = try await ssh.tailLog(lines: 500)
                if !logOutput.isEmpty {
                    print("[Scrollback] Fetched \(logOutput.count) bytes from latest.log")
                    return logOutput
                }
            default:
                break
            }
        } catch {
            print("[Scrollback] Failed to fetch history: \(error)")
        }

        return nil
    }

    /// Start streaming PTY output
    private func startPTYStream(for server: Server) {
        // Cancel existing stream
        ptyStreamTasks[server.id]?.cancel()

        guard let pty = ptyServices[server.id] else { return }

        let serverId = server.id

        // Initialize bridge service (configured with RCON for sending requests)
        let bridge = bridgeService(for: server)

        ptyStreamTasks[server.id] = Task {
            let stream = await pty.streamOutput()
            for await chunk in stream {
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self.lastPTYOutputAt[serverId] = Date()
                }

                // Process through bridge service to detect/handle bridge messages
                let filteredChunk = await MainActor.run {
                    return bridge.processOutput(chunk)
                }

                // Send filtered output to SwiftTerm callback if registered
                await MainActor.run {
                    if let callback = self.ptyOutputCallbacks[serverId] {
                        callback(filteredChunk)
                    }
                }

                // Also process for legacy console messages (can be removed once SwiftTerm is fully integrated)
                await MainActor.run {
                    // Split by newlines but preserve the raw output for ANSI parsing
                    let lines = filteredChunk.components(separatedBy: "\n")
                    for (index, line) in lines.enumerated() {
                        // Skip empty lines except the last one (might be partial)
                        if line.isEmpty && index < lines.count - 1 { continue }
                        if line.isEmpty { continue }

                        // Skip tmux status lines (e.g., "[session:window*    "hostname" HH:MM DD-Mon-YY")
                        if self.isTmuxStatusLine(line) { continue }

                        // Filter out server prompt lines and command echoes
                        if self.shouldFilterLine(line) { continue }

                        if server.consoleMode == .ptyMcwrap {
                            if self.lineIndicatesServerNotRunning(line) {
                                self.lastPTYOutputWasNotRunning[serverId] = true
                            } else {
                                self.lastPTYOutputWasNotRunning[serverId] = false
                            }
                        }

                        // If MCPanelBridge just regenerated commands.json, refresh our cached tree.
                        if self.lineIndicatesBridgeCommandDump(line) {
                            self.scheduleBridgeCommandTreeRefresh(for: serverId, reason: "console:\(line.prefix(64))")
                        }

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

            // Stream ended - mark as disconnected and attempt reconnect if server is restarting
            await MainActor.run {
                self.ptyConnected[serverId] = false

                // If server is restarting, attempt to reconnect after a delay
                if self.serverRestarting[serverId] == true {
                    // Get the server object to reconnect
                    if let server = self.servers.first(where: { $0.id == serverId }) {
                        Task {
                            await self.attemptPTYReconnect(for: server)
                        }
                    }
                }
            }
        }
    }

    /// Watchdog to keep console output alive during restart.
    /// Some backends (notably mcwrap) keep the SSH process alive but stop emitting output after a restart,
    /// requiring a fresh attach. This watchdog forces a clean reattach when output goes stale.
    private func startRestartWatchdog(for server: Server) {
        let serverId = server.id

        restartWatchdogTasks[serverId]?.cancel()
        restartWatchdogTasks[serverId] = Task {
            // Allow the restart command to take effect first.
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            let startedAt = Date()
            var didAttemptReconnect = false
            while !Task.isCancelled, serverRestarting[serverId] == true {
                // Only meaningful for PTY modes.
                guard server.consoleMode != .logTail else {
                    serverRestarting[serverId] = false
                    restartRequestedAt.removeValue(forKey: serverId)
                    break
                }

                // If we've received output recently, keep waiting.
                let lastOutput = await MainActor.run { self.lastPTYOutputAt[serverId] }
                let secondsSinceOutput: TimeInterval = {
                    guard let lastOutput else { return 999 }
                    return Date().timeIntervalSince(lastOutput)
                }()

                // Refresh status occasionally so we know when the server is back.
                await refreshServerStatus(server)

                let isConnected = self.ptyConnected[serverId] == true
                let requestedAt = await MainActor.run { self.restartRequestedAt[serverId] } ?? startedAt

                // If connection is down, reconnect (even if status is unknown).
                if !isConnected {
                    await connectPTY(for: server)
                    didAttemptReconnect = didAttemptReconnect || (self.ptyConnected[serverId] == true)
                }

                // If still "connected" but output is stale for a while, force a fresh attach.
                if self.ptyConnected[serverId] == true && secondsSinceOutput > 8 {
                    print("[PTY] Watchdog: output stale (\(Int(secondsSinceOutput))s). Forcing reattach...")
                    await connectPTY(for: server)
                    didAttemptReconnect = true
                }

                // Consider restart handled once we see *new* output after the restart request
                // and we've attempted at least one reconnect/reattach.
                let notRunningGateSatisfied: Bool = {
                    guard server.consoleMode == .ptyMcwrap else { return true }
                    return self.lastPTYOutputWasNotRunning[serverId] != true
                }()

                if didAttemptReconnect,
                   self.ptyConnected[serverId] == true,
                   let lastOutput,
                   lastOutput > requestedAt,
                   secondsSinceOutput < 2,
                   notRunningGateSatisfied {
                    self.serverRestarting[serverId] = false
                    self.restartRequestedAt.removeValue(forKey: serverId)
                    break
                }

                // Safety: don't keep retrying forever.
                if Date().timeIntervalSince(startedAt) > 90 {
                    print("[PTY] Watchdog: timed out waiting for console output after restart.")
                    self.serverRestarting[serverId] = false
                    self.restartRequestedAt.removeValue(forKey: serverId)
                    break
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func stopRestartWatchdog(for serverId: UUID) {
        restartWatchdogTasks[serverId]?.cancel()
        restartWatchdogTasks.removeValue(forKey: serverId)
        restartRequestedAt.removeValue(forKey: serverId)
    }

    /// Attempt to reconnect PTY after server restart with retries
    private func attemptPTYReconnect(for server: Server, attempt: Int = 1, maxAttempts: Int = 10) async {
        let serverId = server.id

        // Check if we should still be trying to reconnect
        guard serverRestarting[serverId] == true else {
            print("[PTY] Reconnection cancelled - server no longer restarting")
            return
        }

        // Wait before attempting reconnect (longer wait on later attempts)
        let delaySeconds = min(2 + attempt, 10)  // 3s, 4s, 5s, ..., up to 10s
        print("[PTY] Waiting \(delaySeconds)s before reconnect attempt \(attempt)/\(maxAttempts)")
        try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)

        // Check again after sleep
        guard serverRestarting[serverId] == true else {
            print("[PTY] Reconnection cancelled after wait")
            return
        }

        // Try to detect if the session exists
        do {
            let sessions = try await ptyService(for: server).detectSessions()
            let hasMatchingSession: Bool

            switch server.consoleMode {
            case .ptyTmux:
                hasMatchingSession = sessions.contains { $0.type == .tmux && (server.tmuxSession == nil || $0.name == server.tmuxSession) }
            case .ptyScreen:
                // GNU screen reports sessions as "<pid>.<name>". Users often configure just "<name>".
                // Treat either exact match or suffix match as valid.
                if let configured = server.screenSession, !configured.isEmpty {
                    hasMatchingSession = sessions.contains { s in
                        guard s.type == .screen else { return false }
                        return s.name == configured || s.name.hasSuffix(".\(configured)")
                    }
                } else {
                    hasMatchingSession = sessions.contains { $0.type == .screen }
                }
            case .ptyMcwrap:
                // mcwrap creates a new session when server starts
                hasMatchingSession = true
            default:
                hasMatchingSession = !sessions.isEmpty
            }

            if hasMatchingSession {
                print("[PTY] Session found, attempting reconnect...")
                await connectPTY(for: server)

                // Check if reconnection succeeded
                if ptyConnected[serverId] == true {
                    print("[PTY] Reconnected successfully after restart!")
                    serverRestarting[serverId] = false
                    return
                }
            } else {
                print("[PTY] Session not yet available (attempt \(attempt))")
            }
        } catch {
            print("[PTY] Error detecting sessions: \(error)")
        }

        // Retry if we haven't exceeded max attempts
        if attempt < maxAttempts {
            await attemptPTYReconnect(for: server, attempt: attempt + 1, maxAttempts: maxAttempts)
        } else {
            print("[PTY] Max reconnection attempts reached, giving up")
            serverRestarting[serverId] = false
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

    /// Check if a line should be filtered (standalone prompts, empty log lines)
    private func shouldFilterLine(_ line: String) -> Bool {
        // Strip ANSI escape sequences for pattern matching
        let stripped = stripANSIAndTrim(line)

        // Filter standalone prompt lines (just ">") - these are redundant with our UI prompt
        if stripped == ">" || stripped == "> " {
            return true
        }

        // Filter empty log lines (timestamp prefix with no content after OSC stripping)
        // Matches patterns like "[HH:MM:SS INFO]:" or "[HH:MM:SS WARN]:" with nothing after
        let emptyLogPattern = #"^\[\d{2}:\d{2}:\d{2}\s+(INFO|WARN|ERROR|DEBUG)\]:?\s*$"#
        if stripped.range(of: emptyLogPattern, options: .regularExpression) != nil {
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

    // MARK: - Dynamic Command Discovery

    /// Discover available commands from the server
    /// Uses MCPanel Bridge commands.json file exclusively
    func scrapeServerCommands(for server: Server) {
        // Cancel any existing discovery task
        commandDiscoveryTask[server.id]?.cancel()

        commandDiscoveryTask[server.id] = Task {
            // Brief delay to let connection stabilize
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

            guard !Task.isCancelled else { return }

            let logger = DebugLogger.shared
            logger.log("Starting command discovery for server", category: .commands)

            // Use MCPanel Bridge commands.json file via SSH
            let bridge = bridgeService(for: server)
            await bridge.fetchCommandTree()

            if let bridgeTree = bridge.commandTree {
                var tree = BrigadierCommandTree()
                tree.rootCommands = Set(bridgeTree.commands.keys)

                for (name, node) in bridgeTree.commands {
                    if let children = node.children {
                        tree.subcommands[name.lowercased()] = Set(children.keys)
                    }
                }

                let oCommands = tree.rootCommands.filter { $0.lowercased().hasPrefix("o") }
                logger.log("Found \(tree.rootCommands.count) commands from Bridge, 'o' commands: \(oCommands.sorted())", category: .commands)
                await MainActor.run {
                    self.commandTree[server.id] = tree
                    self.commandTreeUpdateCount += 1
                }
            } else {
                logger.log("No commands discovered from Bridge - autocomplete will use history only", category: .commands)
            }
        }
    }

    /// Get all known commands for a server (discovered + history)
    func allKnownCommands(for server: Server) -> [String] {
        var commands = Set<String>()

        // Add discovered commands from Brigadier tree
        if let tree = commandTree[server.id] {
            commands.formUnion(tree.rootCommands)
        }

        // Add commands from history
        if let history = commandHistory[server.id] {
            for cmd in history.commands {
                let parts = cmd.split(separator: " ", maxSplits: 1)
                if let root = parts.first {
                    commands.insert(String(root).lowercased())
                }
            }
        }

        return commands.sorted()
    }

    /// Get subcommands for a specific command (for hierarchical suggestions)
    func getSubcommands(for command: String, server: Server) -> [String] {
        return commandTree[server.id]?.getSubcommands(for: command) ?? []
    }

    /// Check if a command has subcommands
    func hasSubcommands(for command: String, server: Server) -> Bool {
        return commandTree[server.id]?.hasSubcommands(command) ?? false
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
