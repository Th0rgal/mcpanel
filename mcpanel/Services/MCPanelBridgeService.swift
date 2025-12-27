//
//  MCPanelBridgeService.swift
//  MCPanel
//
//  Service for communicating with MCPanel Bridge plugin on servers
//

import Foundation
import Combine

/// Service that manages communication with the MCPanel Bridge plugin.
/// Detects bridge presence and provides enhanced features when available.
@MainActor
class MCPanelBridgeService: ObservableObject {

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

    /// Latest player list from bridge
    @Published var playerList: PlayerListPayload?

    /// Latest server status from bridge
    @Published var serverStatus: ServerStatusPayload?

    // MARK: - Private State

    /// Server reference for RCON access
    private var server: Server?

    /// SSH service for RCON commands
    private var sshService: SSHService?

    // MARK: - Initialization

    init() {}

    /// Configure RCON for sending requests
    /// This is the cleaner approach - requests go via RCON, responses come via OSC
    func configure(server: Server, sshService: SSHService) {
        self.server = server
        self.sshService = sshService
    }

    // MARK: - Message Processing

    /// Process incoming PTY data to detect and handle bridge messages.
    /// Returns the filtered data with bridge messages removed.
    func processOutput(_ data: String) -> String {
        guard MCPanelBridgeProtocol.containsMessage(data) else {
            return data
        }

        // Extract messages
        let messages = MCPanelBridgeProtocol.extractMessages(data)

        for message in messages {
            switch message {
            case .response(let response):
                handleResponse(response)
            case .event(let event):
                handleEvent(event)
            }
        }

        // Return filtered output (without OSC messages)
        return MCPanelBridgeProtocol.filterConsoleOutput(data)
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: MCPanelEvent) {
        print("[Bridge] Received event: \(event.event)")

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

        default:
            print("[Bridge] Unknown event: \(event.event)")
        }
    }

    // MARK: - Response Handling (legacy OSC, kept for events)

    private func handleResponse(_ response: MCPanelResponse) {
        print("[Bridge] Received OSC response: \(response.type) for request \(response.id)")
        // Note: Responses now come directly via RCON, this is only for backwards compatibility
        updateCachedData(from: response)
    }

    // MARK: - Request Sending

    /// Send a request to the bridge via RCON and get response directly.
    /// The bridge returns the response in sender.sendMessage(), which is captured by RCON.
    /// This is synchronous and doesn't depend on PTY/stdout for responses.
    func sendRequest(_ request: MCPanelRequest, timeout: TimeInterval = 5.0) async throws -> MCPanelResponse {
        guard bridgeDetected else {
            throw BridgeError.notDetected
        }

        guard let server = server,
              let sshService = sshService,
              let rconPassword = server.rconPassword,
              !rconPassword.isEmpty else {
            throw BridgeError.rconNotConfigured
        }

        let rconHost = server.rconHost ?? "127.0.0.1"
        let rconPort = server.rconPort ?? 25575

        // Encode request as console command (mcpanel <base64>)
        let requestCommand = MCPanelBridgeProtocol.encodeRequest(request)

        // Send request via RCON and get response directly
        let rconOutput = try await sshService.sendRCONCommand(
            requestCommand,
            password: rconPassword,
            port: rconPort,
            host: rconHost
        )

        // Parse the RCON output for the MCPanel response
        // Format: MCPANEL:<base64-json>
        guard let response = MCPanelBridgeProtocol.parseRCONResponse(rconOutput) else {
            print("[Bridge] Failed to parse RCON response: \(rconOutput)")
            throw BridgeError.invalidResponse
        }

        // Update cached data based on response type
        updateCachedData(from: response)

        return response
    }

    /// Update cached data from a response
    private func updateCachedData(from response: MCPanelResponse) {
        switch response.type {
        case "command_tree":
            if let payload = response.payload.decode(CommandTreePayload.self) {
                commandTree = payload
            }
        case "player_list":
            if let payload = response.payload.decode(PlayerListPayload.self) {
                playerList = payload
            }
        case "server_status":
            if let payload = response.payload.decode(ServerStatusPayload.self) {
                serverStatus = payload
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
            return []
        }

        // Remove leading slash if present
        let cleanBuffer = buffer.hasPrefix("/") ? String(buffer.dropFirst()) : buffer

        // Split buffer into parts
        let parts = cleanBuffer.components(separatedBy: " ")
        guard !parts.isEmpty else { return [] }

        // If only one part (or part with no space), complete command names
        if parts.count == 1 {
            let prefix = parts[0].lowercased()
            return commandTree.commands.keys
                .filter { $0.lowercased().hasPrefix(prefix) }
                .sorted()
                .prefix(50)
                .map { CompletionPayload.Completion(text: $0, tooltip: commandTree.commands[$0]?.description) }
        }

        // Multiple parts - try to complete subcommands/arguments
        let commandName = parts[0].lowercased()
        guard let commandNode = commandTree.commands[commandName] else {
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
            return []
        }

        return getCompletionsFromChildren(children, prefix: partialArg)
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
            if node.isArgument {
                // For arguments, show examples if available
                if let examples = node.examples, !examples.isEmpty {
                    for example in examples {
                        if example.lowercased().hasPrefix(lowercasedPrefix) {
                            let tooltip = node.type.map { "(\($0))" }
                            completions.append(CompletionPayload.Completion(text: example, tooltip: tooltip))
                        }
                    }
                } else {
                    // Show placeholder like <player> with type info
                    let tooltip = node.type.map { "Type: \($0)" }
                    completions.append(CompletionPayload.Completion(text: key, tooltip: tooltip))
                }
            } else {
                // Literal (subcommand) - match prefix
                if key.lowercased().hasPrefix(lowercasedPrefix) {
                    completions.append(CompletionPayload.Completion(text: key, tooltip: node.description))
                }
            }
        }

        return completions.sorted { $0.text < $1.text }.prefix(50).map { $0 }
    }

    /// Fetch the command tree from the commands.json file via SFTP.
    /// This is generated by the bridge plugin on startup and after /reload.
    func fetchCommandTree() async {
        guard let server = server, let sshService = sshService else {
            print("[Bridge] fetchCommandTree: server or sshService is nil")
            return
        }

        // Path to commands.json in the plugin's data folder
        let commandsPath = "\(server.effectivePluginsPath)/MCPanelBridge/commands.json"
        print("[Bridge] Fetching command tree from: \(commandsPath)")

        do {
            // Read the file via SFTP
            let jsonData = try await sshService.readFile(at: commandsPath)
            print("[Bridge] Read \(jsonData.count) bytes from commands.json")

            if let payload = try? JSONDecoder().decode(CommandTreePayload.self, from: jsonData) {
                commandTree = payload
                let oCommands = payload.commands.keys.filter { $0.hasPrefix("o") }
                print("[Bridge] Loaded \(payload.commands.count) commands, starting with 'o': \(oCommands.sorted())")
            } else {
                print("[Bridge] Failed to decode CommandTreePayload from JSON")
                // Try to see the raw JSON for debugging
                if let jsonString = String(data: jsonData, encoding: .utf8)?.prefix(500) {
                    print("[Bridge] Raw JSON preview: \(jsonString)")
                }
            }
        } catch {
            print("[Bridge] Failed to fetch commands.json: \(error)")
            // Fall back to RCON if file not found
            await fetchCommandTreeViaRCON()
        }
    }

    /// Fallback: Fetch command tree via RCON if SFTP fails.
    private func fetchCommandTreeViaRCON() async {
        guard bridgeDetected else { return }

        do {
            let response = try await sendRequest(.commands())
            if let payload = response.payload.decode(CommandTreePayload.self) {
                commandTree = payload
                print("[Bridge] Fetched \(payload.commands.count) commands via RCON")
            }
        } catch {
            print("[Bridge] Command tree fetch via RCON failed: \(error)")
        }
    }

    /// Fetch player list from the bridge.
    func fetchPlayers() async {
        guard bridgeDetected else { return }

        do {
            let response = try await sendRequest(.players())
            if let payload = response.payload.decode(PlayerListPayload.self) {
                playerList = payload
            }
        } catch {
            print("[Bridge] Player list fetch failed: \(error)")
        }
    }

    /// Fetch server status from the bridge.
    func fetchStatus() async {
        guard bridgeDetected else { return }

        do {
            let response = try await sendRequest(.status())
            if let payload = response.payload.decode(ServerStatusPayload.self) {
                serverStatus = payload
            }
        } catch {
            print("[Bridge] Status fetch failed: \(error)")
        }
    }

    // MARK: - Bridge Detection

    /// Reset bridge state (e.g., on disconnect)
    func reset() {
        bridgeDetected = false
        bridgeVersion = nil
        platform = nil
        features = []
        commandTree = nil
        playerList = nil
        serverStatus = nil
    }

    /// Check if bridge supports a specific feature
    func hasFeature(_ feature: String) -> Bool {
        return bridgeDetected && features.contains(feature)
    }
}

// MARK: - Errors

enum BridgeError: LocalizedError {
    case notDetected
    case rconNotConfigured
    case rconFailed(String)
    case timeout
    case disconnected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notDetected:
            return "MCPanel Bridge plugin not detected on server"
        case .rconNotConfigured:
            return "RCON not configured - set RCON password in server settings"
        case .rconFailed(let message):
            return "RCON request failed: \(message)"
        case .timeout:
            return "Request timed out"
        case .disconnected:
            return "Disconnected from server"
        case .invalidResponse:
            return "Invalid response from bridge"
        }
    }
}
