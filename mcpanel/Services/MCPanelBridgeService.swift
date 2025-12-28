//
//  MCPanelBridgeService.swift
//  MCPanel
//
//  Service for communicating with MCPanel Bridge plugin on servers
//

import Foundation
import Combine

// MARK: - Performance History

/// Stores time-series performance data for charts and sparklines
@MainActor
class PerformanceHistory: ObservableObject {

    struct DataPoint: Identifiable {
        let id = UUID()
        let timestamp: Date
        let value: Double
    }

    /// Full resolution: last 30 min at 500ms = 3,600 points
    @Published var tpsHistory: [DataPoint] = []
    @Published var msptHistory: [DataPoint] = []
    @Published var memoryHistory: [DataPoint] = []
    @Published var playerCountHistory: [DataPoint] = []

    private let maxRecentSamples = 3600  // 30 min × 2/sec

    /// Downsampled: last 6 hours at 30s averages = 720 points
    @Published var hourlyTpsHistory: [DataPoint] = []
    @Published var hourlyMemoryHistory: [DataPoint] = []

    private let maxHourlySamples = 720

    /// Track when we last downsampled
    private var lastDownsampleTime: Date = Date()
    private let downsampleInterval: TimeInterval = 30  // Downsample every 30 seconds

    /// Add a new sample from status update
    func addSample(_ status: StatusUpdatePayload) {
        let now = Date()

        // Add to recent history
        tpsHistory.append(DataPoint(timestamp: now, value: status.tps))
        if let mspt = status.mspt {
            msptHistory.append(DataPoint(timestamp: now, value: mspt))
        }
        let memoryPercent = Double(status.usedMemoryMB) / Double(max(status.maxMemoryMB, 1)) * 100
        memoryHistory.append(DataPoint(timestamp: now, value: memoryPercent))
        playerCountHistory.append(DataPoint(timestamp: now, value: Double(status.playerCount)))

        // Trim old data
        trimHistory()

        // Downsample for hourly history
        if now.timeIntervalSince(lastDownsampleTime) >= downsampleInterval {
            downsampleToHourly()
            lastDownsampleTime = now
        }
    }

    /// Trim recent history to keep within memory limits
    private func trimHistory() {
        if tpsHistory.count > maxRecentSamples {
            tpsHistory.removeFirst(tpsHistory.count - maxRecentSamples)
        }
        if msptHistory.count > maxRecentSamples {
            msptHistory.removeFirst(msptHistory.count - maxRecentSamples)
        }
        if memoryHistory.count > maxRecentSamples {
            memoryHistory.removeFirst(memoryHistory.count - maxRecentSamples)
        }
        if playerCountHistory.count > maxRecentSamples {
            playerCountHistory.removeFirst(playerCountHistory.count - maxRecentSamples)
        }
    }

    /// Create downsampled hourly averages
    private func downsampleToHourly() {
        let now = Date()

        // Average recent TPS samples (last 30 seconds worth = ~60 samples at 500ms)
        let recentTps = tpsHistory.suffix(60)
        if !recentTps.isEmpty {
            let avgTps = recentTps.reduce(0.0) { $0 + $1.value } / Double(recentTps.count)
            hourlyTpsHistory.append(DataPoint(timestamp: now, value: avgTps))

            if hourlyTpsHistory.count > maxHourlySamples {
                hourlyTpsHistory.removeFirst()
            }
        }

        // Average recent memory samples
        let recentMem = memoryHistory.suffix(60)
        if !recentMem.isEmpty {
            let avgMem = recentMem.reduce(0.0) { $0 + $1.value } / Double(recentMem.count)
            hourlyMemoryHistory.append(DataPoint(timestamp: now, value: avgMem))

            if hourlyMemoryHistory.count > maxHourlySamples {
                hourlyMemoryHistory.removeFirst()
            }
        }
    }

    /// Clear all history (e.g., on disconnect)
    func clear() {
        tpsHistory = []
        msptHistory = []
        memoryHistory = []
        playerCountHistory = []
        hourlyTpsHistory = []
        hourlyMemoryHistory = []
    }
}

/// Service that manages communication with the MCPanel Bridge plugin.
/// Detects bridge presence and provides enhanced features when available.
@MainActor
class MCPanelBridgeService: ObservableObject {

    private let logger = DebugLogger.shared

    // MARK: - Published State

    /// Whether the bridge plugin is detected on this server
    @Published var bridgeDetected: Bool = false

    /// Bridge version if detected
    @Published var bridgeVersion: String?

    /// Platform (paper, spigot, velocity, etc.)
    @Published var platform: String?

    /// Available features from the bridge
    @Published var features: Set<String> = []

    /// Latest command tree from bridge
    @Published var commandTree: CommandTreePayload?

    /// Latest server status from periodic broadcasts
    @Published var serverStatus: StatusUpdatePayload?

    /// Latest player list from periodic broadcasts
    @Published var playerList: PlayersUpdatePayload?

    /// Plugin registries (key: "plugin:type", value: list of values)
    @Published var registries: [String: [String]] = [:]

    /// Performance history for charts and sparklines
    @Published var performanceHistory = PerformanceHistory()

    /// Whether dashboard is active (for high-frequency updates)
    @Published var dashboardActive: Bool = false

    // MARK: - Private State

    /// Server reference for SSH access
    private var server: Server?

    /// SSH service for file operations
    private var sshService: SSHService?

    /// Trailing partial OSC sequence carried across chunks
    private var pendingOSCFragment: String = ""

    /// Last attempt to load commands.json (throttle reconnect bursts)
    private var lastCommandTreeFetchAt: Date?

    // MARK: - Initialization

    init() {}

    /// Configure server and SSH service for file operations
    func configure(server: Server, sshService: SSHService) {
        self.server = server
        self.sshService = sshService
    }

    // MARK: - Message Processing

    /// Process incoming PTY data to detect and handle bridge messages.
    /// Returns the filtered data with bridge messages removed.
    func processOutput(_ data: String, allowPartialBuffer: Bool = true) -> String {
        let complete: String
        if allowPartialBuffer {
            let combined = pendingOSCFragment + data
            let split = MCPanelBridgeProtocol.splitTrailingIncompleteOSC(combined)
            pendingOSCFragment = split.remainder
            complete = split.complete
        } else {
            let split = MCPanelBridgeProtocol.splitTrailingIncompleteOSC(data)
            complete = split.complete
        }

        guard MCPanelBridgeProtocol.containsMessage(complete) else {
            return complete
        }

        // Extract messages
        let messages = MCPanelBridgeProtocol.extractMessages(complete)

        for message in messages {
            switch message {
            case .response(let response):
                handleResponse(response)
            case .event(let event):
                handleEvent(event)
            }
        }

        // Return filtered output (without OSC messages)
        return MCPanelBridgeProtocol.filterConsoleOutput(complete)
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: MCPanelEvent) {
        logger.log("[Bridge] Received event: \(event.event)", category: .bridge, verbose: true)

        switch event.event {
        case "mcpanel_bridge_ready":
            if let payload = event.payload?.decode(BridgeReadyPayload.self) {
                bridgeDetected = true
                bridgeVersion = payload.version
                platform = payload.platform
                features = Set(payload.features)
                print("[Bridge] Bridge ready - v\(payload.version) on \(payload.platform)")
                print("[Bridge] Features: \(payload.features)")

                // Automatically fetch command tree when bridge is detected
                Task {
                    await fetchCommandTree()
                }
            }

        case "player_join":
            if let payload = event.payload?.value as? [String: Any],
               let name = payload["name"] as? String {
                print("[Bridge] Player joined: \(name)")
                // Could trigger player list refresh
            }

        case "player_leave":
            if let payload = event.payload?.value as? [String: Any],
               let name = payload["name"] as? String {
                print("[Bridge] Player left: \(name)")
            }

        case "server_ready":
            print("[Bridge] Server finished loading")
            // Refresh command tree after server reload
            Task {
                await fetchCommandTree()
            }

        case "status_update":
            if let payload = event.payload?.decode(StatusUpdatePayload.self) {
                serverStatus = payload
                // If we receive status updates, the bridge is definitely working
                // (mcpanel_bridge_ready may have been sent before we connected)
                if !bridgeDetected {
                    bridgeDetected = true
                    print("[Bridge] Bridge detected via status_update (missed mcpanel_bridge_ready)")
                }
                // Record to performance history for charts
                performanceHistory.addSample(payload)
                // Check for performance alerts
                if let server = server {
                    PerformanceAlertService.shared.checkPerformance(
                        status: payload,
                        serverName: server.name,
                        serverId: server.id
                    )
                }
                logger.log("[Bridge] Status update: TPS=\(String(format: "%.1f", payload.tps)), Players=\(payload.playerCount)/\(payload.maxPlayers), Memory=\(payload.usedMemoryMB)/\(payload.maxMemoryMB)MB", category: .bridge, verbose: true)
            }

        case "players_update":
            if let payload = event.payload?.decode(PlayersUpdatePayload.self) {
                playerList = payload
                // If we receive player updates, the bridge is definitely working
                if !bridgeDetected {
                    bridgeDetected = true
                    print("[Bridge] Bridge detected via players_update (missed mcpanel_bridge_ready)")
                }
                logger.log("[Bridge] Players update: \(payload.count) players online", category: .bridge, verbose: true)
            }

        case "registry_update":
            if let payload = event.payload?.decode(RegistryUpdatePayload.self) {
                let key = "\(payload.plugin):\(payload.type)"
                registries[key] = payload.values
                logger.log("[Bridge] Registry update: \(key) with \(payload.values.count) values", category: .bridge)
            }

        case "commands_updated":
            if let payload = event.payload?.decode(CommandsUpdatedPayload.self) {
                logger.log("[Bridge] Commands updated: \(payload.reason)", category: .bridge)
                // Refresh command tree from the updated commands.json
                Task {
                    await fetchCommandTree()
                }
            }

        default:
            print("[Bridge] Unknown event: \(event.event)")
        }
    }

    // MARK: - Response Handling (legacy OSC, kept for events)

    private func handleResponse(_ response: MCPanelResponse) {
        print("[Bridge] Received OSC response: \(response.type) for request \(response.id)")
        // Update cached data based on response type
        switch response.type {
        case "command_tree":
            if let payload = response.payload.decode(CommandTreePayload.self) {
                commandTree = payload
            }
        default:
            break
        }
    }

    // MARK: - High-Level API

    /// Get tab completions for a command buffer using the cached command tree.
    /// This is done locally without any RCON calls - fast and doesn't spam the console.
    func getCompletions(buffer: String) -> [CompletionPayload.Completion] {
        guard let commandTree = commandTree else {
            logger.log("getCompletions: no command tree available (self.commandTree is nil)", category: .commands)
            return []
        }
        logger.log("getCompletions: commandTree has \(commandTree.commands.count) commands", category: .commands, verbose: true)

        // Remove leading slash if present
        let cleanBuffer = buffer.hasPrefix("/") ? String(buffer.dropFirst()) : buffer

        // Split buffer into parts
        let parts = cleanBuffer.components(separatedBy: " ")
        guard !parts.isEmpty else { return [] }

        // If only one part (or part with no space), complete command names
        if parts.count == 1 {
            let prefix = parts[0].lowercased()
            let results = commandTree.commands.keys
                .filter { $0.lowercased().hasPrefix(prefix) }
                .sorted()
                .prefix(50)
                .map { key -> CompletionPayload.Completion in
                    let node = commandTree.commands[key]
                    let hasChildren = node?.children != nil && !(node?.children?.isEmpty ?? true)
                    return CompletionPayload.Completion(text: key, tooltip: node?.description, hasChildren: hasChildren)
                }
            logger.logAutocomplete(prefix: prefix, resultCount: results.count)
            return results
        }

        // Multiple parts - try to complete subcommands/arguments
        let commandName = parts[0].lowercased()

        // Try exact match first, then case-insensitive
        var commandNode: CommandTreePayload.CommandNode?
        if let node = commandTree.commands[commandName] {
            commandNode = node
        } else {
            // Case-insensitive fallback
            for (key, node) in commandTree.commands {
                if key.lowercased() == commandName {
                    commandNode = node
                    break
                }
            }
        }

        guard let commandNode = commandNode else {
            logger.log("getCompletions: command '\(commandName)' not found in tree (keys: \(commandTree.commands.keys.filter { $0.lowercased().hasPrefix(commandName.prefix(2)) }.sorted()))", category: .commands, verbose: true)
            return []
        }

        // Walk down the command tree to find where we are
        var currentNode = commandNode
        var currentParts = Array(parts.dropFirst())

        // Navigate through completed subcommands/arguments
        while currentParts.count > 1 {
            let typedValue = currentParts[0]
            guard let children = currentNode.children else {
                return []
            }

            // Try to find a matching child node
            if let nextNode = findMatchingChild(in: children, for: typedValue) {
                currentNode = nextNode
                currentParts = Array(currentParts.dropFirst())
            } else {
                // Can't navigate further, no completions available
                return []
            }
        }

        // Complete the last part against children
        let partialArg = currentParts.last ?? ""

        guard let children = currentNode.children else {
            logger.log("getCompletions: no children for '\(parts.joined(separator: " "))' - node has no children", category: .commands)
            return []
        }

        logger.log("getCompletions: found \(children.count) children for '\(commandName)', partial='\(partialArg)'", category: .commands, verbose: true)
        let results = getCompletionsFromChildren(children, prefix: partialArg)
        logger.logAutocomplete(prefix: cleanBuffer, resultCount: results.count)
        return results
    }

    /// Find a matching child node for the typed value.
    /// For literals, matches exact name. For arguments, any value matches.
    private func findMatchingChild(
        in children: [String: CommandTreePayload.CommandNode],
        for typedValue: String
    ) -> CommandTreePayload.CommandNode? {
        let lowercased = typedValue.lowercased()

        // First try exact literal match
        if let literalNode = children[lowercased], !literalNode.isArgument {
            return literalNode
        }

        // Also try case-insensitive literal match
        for (key, node) in children {
            if !node.isArgument && key.lowercased() == lowercased {
                return node
            }
        }

        // For arguments (keys like <name>), any value matches
        // Return the first argument node found
        for (key, node) in children {
            if key.hasPrefix("<") && key.hasSuffix(">") {
                return node
            }
        }

        return nil
    }

    /// Get completions from children nodes.
    /// Shows literal names and argument examples/placeholders.
    private func getCompletionsFromChildren(
        _ children: [String: CommandTreePayload.CommandNode],
        prefix: String
    ) -> [CompletionPayload.Completion] {
        var completions: [CompletionPayload.Completion] = []
        let lowercasedPrefix = prefix.lowercased()

        for (key, node) in children {
            let hasChildren = node.children != nil && !(node.children?.isEmpty ?? true)
            // Some exports omit `type` for argument nodes but still name them like "<arg>".
            // Treat any "<...>" key as an argument node so we don't surface placeholders as literals.
            let isArgumentNode = node.isArgument || (key.hasPrefix("<") && key.hasSuffix(">"))

            if isArgumentNode {
                // For arguments, show examples if available
                if let examples = node.examples, !examples.isEmpty {
                    for example in examples {
                        if example.lowercased().hasPrefix(lowercasedPrefix) {
                            let tooltip = node.type.map { "(\($0))" }
                            // Examples are real values that can be inserted
                            completions.append(CompletionPayload.Completion(text: example, tooltip: tooltip, hasChildren: hasChildren, isTypeHint: false))
                        }
                    }
                } else {
                    // No examples - only show a placeholder when the user hasn't started typing yet.
                    // This is a type hint (shouldn't be inserted literally).
                    if lowercasedPrefix.isEmpty {
                        // Format: show the type name, not <argname>, when available.
                        let displayText = node.type ?? key.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
                        let tooltip = "Type a \(displayText) value"
                        completions.append(CompletionPayload.Completion(text: "<\(displayText)>", tooltip: tooltip, hasChildren: hasChildren, isTypeHint: true))
                    }
                }
            } else {
                // Literal (subcommand) - match prefix
                if key.lowercased().hasPrefix(lowercasedPrefix) {
                    completions.append(CompletionPayload.Completion(text: key, tooltip: node.description, hasChildren: hasChildren, isTypeHint: false))
                }
            }
        }

        return completions.sorted { $0.text < $1.text }.prefix(50).map { $0 }
    }

    /// Fetch the command tree from the commands.json file via SSH cat.
    /// This is generated by the bridge plugin on startup and after /reload.
    func fetchCommandTree() async {
        guard let server = server, let sshService = sshService else {
            logger.log("fetchCommandTree: server or sshService is nil", category: .bridge)
            return
        }

        // Path to commands.json in the plugin's data folder
        let commandsPath = "\(server.effectivePluginsPath)/MCPanelBridge/commands.json"
        logger.logCommandTreeFetch(serverPath: commandsPath, method: "SSH")

        do {
            // Use a quick check + read to avoid hanging on non-existent files
            // The -e test returns quickly if file doesn't exist
            let jsonString = try await sshService.readFileQuick(at: commandsPath)

            guard let jsonData = jsonString.data(using: .utf8), !jsonString.isEmpty else {
                logger.log("commands.json is empty or not found", category: .commands)
                return
            }

            logger.log("Read \(jsonData.count) bytes from commands.json", category: .commands)

            if let payload = try? JSONDecoder().decode(CommandTreePayload.self, from: jsonData) {
                commandTree = payload
                logger.logCommandTreeResult(commandCount: payload.commands.count, source: "SSH/commands.json")

                // Log some sample commands for debugging
                let sampleCommands = payload.commands.keys.sorted().prefix(10)
                logger.log("Sample commands: \(sampleCommands.joined(separator: ", "))", category: .commands, verbose: true)

                // Log commands with children (subcommands)
                let commandsWithChildren = payload.commands.filter { $0.value.children != nil && !($0.value.children?.isEmpty ?? true) }
                logger.log("Commands with children: \(commandsWithChildren.count)", category: .commands)

                // Log oraxen specifically - check both cases
                let oraxenKeys = payload.commands.keys.filter { $0.lowercased() == "oraxen" }
                logger.log("oraxen key variations: \(oraxenKeys)", category: .commands)
                if let oraxen = payload.commands["oraxen"] ?? payload.commands["Oraxen"] {
                    logger.log("oraxen children: \(oraxen.children?.keys.sorted().prefix(10) ?? [])", category: .commands)
                }
            } else {
                logger.log("Failed to decode CommandTreePayload from JSON", category: .commands)
                // Try to see the raw JSON for debugging
                let preview = String(jsonString.prefix(500))
                logger.log("Raw JSON preview: \(preview)", category: .commands, verbose: true)
            }
        } catch {
            logger.logCommandTreeError(error, source: "SSH/commands.json")
        }
    }

    /// Ensure command tree is loaded at least once, with a simple throttle.
    func fetchCommandTreeIfNeeded(minInterval: TimeInterval = 5) async {
        if commandTree != nil { return }

        if let last = lastCommandTreeFetchAt, Date().timeIntervalSince(last) < minInterval {
            return
        }
        lastCommandTreeFetchAt = Date()
        await fetchCommandTree()
    }

    // MARK: - Bridge Detection

    /// Reset bridge state (e.g., on disconnect)
    func reset() {
        bridgeDetected = false
        bridgeVersion = nil
        platform = nil
        features = []
        commandTree = nil
        serverStatus = nil
        playerList = nil
        registries = [:]
        performanceHistory.clear()
        dashboardActive = false
        pendingOSCFragment = ""
        lastCommandTreeFetchAt = nil
    }

    /// Check if bridge supports a specific feature
    func hasFeature(_ feature: String) -> Bool {
        return bridgeDetected && features.contains(feature)
    }

    /// Get registry values for a specific plugin and type (e.g., "oraxen:items")
    func getRegistryValues(plugin: String, type: String) -> [String] {
        return registries["\(plugin):\(type)"] ?? []
    }

    /// Get completions from a registry, filtered by prefix
    func getRegistryCompletions(plugin: String, type: String, prefix: String) -> [CompletionPayload.Completion] {
        let values = getRegistryValues(plugin: plugin, type: type)
        let lowercasedPrefix = prefix.lowercased()

        return values
            .filter { $0.lowercased().hasPrefix(lowercasedPrefix) }
            .prefix(50)
            .map { CompletionPayload.Completion(text: $0, tooltip: "\(plugin) \(type)", hasChildren: false, isTypeHint: false) }
    }
}

// MARK: - Errors

enum BridgeError: LocalizedError {
    case notDetected
    case timeout
    case disconnected

    var errorDescription: String? {
        switch self {
        case .notDetected:
            return "MCPanel Bridge plugin not detected on server"
        case .timeout:
            return "Request timed out"
        case .disconnected:
            return "Disconnected from server"
        }
    }
}
