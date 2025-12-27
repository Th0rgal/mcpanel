//
//  MCPanelBridgeProtocol.swift
//  MCPanel
//
//  Protocol definitions for communicating with MCPanel Bridge plugin
//

import Foundation

// MARK: - OSC Encoding/Decoding

/// Utility for encoding/decoding MCPanel Bridge protocol messages.
/// Messages use iTerm2 OSC sequence format: \x1B]1337;MCPanel:<base64>\x07 (for events)
/// RCON responses use simple format: MCPANEL:<base64-json>
struct MCPanelBridgeProtocol {

    private static let oscPrefix = "\u{1B}]1337;MCPanel:"
    private static let oscSuffix = "\u{07}"

    /// RCON response prefix (simpler format for RCON transmission)
    private static let rconPrefix = "MCPANEL:"

    /// Command prefix for sending requests via console command.
    /// This is sent as a registered Bukkit command to be handled by the plugin.
    private static let commandName = "mcpanel"

    /// Encode a request as a console command.
    /// Format: mcpanel <base64-json>
    /// The MCPanelBridge plugin handles this as a registered command.
    static func encodeRequest(_ request: MCPanelRequest) -> String {
        guard let jsonData = try? JSONEncoder().encode(request),
              let json = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        let base64 = Data(json.utf8).base64EncodedString()
        return "\(commandName) \(base64)"
    }

    // MARK: - RCON Response Parsing

    /// Check if the RCON output contains an MCPanel response
    static func containsRCONResponse(_ data: String) -> Bool {
        return data.contains(rconPrefix)
    }

    /// Parse an MCPanel response from RCON output.
    /// Format: MCPANEL:<base64-json>
    static func parseRCONResponse(_ data: String) -> MCPanelResponse? {
        // Find the MCPANEL: prefix
        guard let prefixRange = data.range(of: rconPrefix) else {
            return nil
        }

        // Extract base64 content (everything after MCPANEL: until newline or end)
        let afterPrefix = data[prefixRange.upperBound...]
        let base64End = afterPrefix.firstIndex(of: "\n") ?? afterPrefix.endIndex
        let base64 = String(afterPrefix[..<base64End]).trimmingCharacters(in: .whitespaces)

        // Decode base64 to JSON
        guard let jsonData = Data(base64Encoded: base64) else {
            return nil
        }

        // Parse as MCPanelResponse
        return try? JSONDecoder().decode(MCPanelResponse.self, from: jsonData)
    }

    /// Check if data contains an OSC-encoded MCPanel message
    static func containsMessage(_ data: String) -> Bool {
        return data.contains(oscPrefix)
    }

    /// Extract and decode all MCPanel messages from a string (console output)
    static func extractMessages(_ data: String) -> [MCPanelMessageWrapper] {
        var messages: [MCPanelMessageWrapper] = []
        var remaining = data

        while let prefixRange = remaining.range(of: oscPrefix) {
            // Find the suffix
            let afterPrefix = remaining[prefixRange.upperBound...]
            guard let suffixRange = afterPrefix.range(of: oscSuffix) else {
                break
            }

            // Extract base64 content
            let base64 = String(afterPrefix[..<suffixRange.lowerBound])

            // Decode
            if let jsonData = Data(base64Encoded: base64) {
                // Try parsing as different message types
                if let response = try? JSONDecoder().decode(MCPanelResponse.self, from: jsonData) {
                    messages.append(.response(response))
                } else if let event = try? JSONDecoder().decode(MCPanelEvent.self, from: jsonData) {
                    messages.append(.event(event))
                }
            }

            // Continue after this message
            remaining = String(remaining[suffixRange.upperBound...])
        }

        return messages
    }

    /// Filter out OSC messages from console output (so they don't display)
    static func filterConsoleOutput(_ data: String) -> String {
        var result = data

        // Remove all OSC sequences
        while let prefixRange = result.range(of: oscPrefix) {
            let afterPrefix = result[prefixRange.upperBound...]
            if let suffixRange = afterPrefix.range(of: oscSuffix) {
                // Remove the entire OSC sequence
                result.removeSubrange(prefixRange.lowerBound...suffixRange.upperBound)
            } else {
                break
            }
        }

        return result
    }
}

// MARK: - Message Wrapper

enum MCPanelMessageWrapper {
    case response(MCPanelResponse)
    case event(MCPanelEvent)
}

// MARK: - Request Types

struct MCPanelRequest: Codable {
    let id: String
    let type: RequestType
    var payload: [String: String]?

    enum RequestType: String, Codable {
        case complete = "COMPLETE"
        case commands = "COMMANDS"
        case players = "PLAYERS"
        case status = "STATUS"
        case plugins = "PLUGINS"
        case worlds = "WORLDS"
        case ping = "PING"
    }

    init(type: RequestType, payload: [String: String]? = nil) {
        self.id = UUID().uuidString.prefix(8).lowercased()
        self.type = type
        self.payload = payload
    }

    static func complete(buffer: String) -> MCPanelRequest {
        MCPanelRequest(type: .complete, payload: ["buffer": buffer])
    }

    static func commands() -> MCPanelRequest {
        MCPanelRequest(type: .commands)
    }

    static func players() -> MCPanelRequest {
        MCPanelRequest(type: .players)
    }

    static func status() -> MCPanelRequest {
        MCPanelRequest(type: .status)
    }

    static func plugins() -> MCPanelRequest {
        MCPanelRequest(type: .plugins)
    }
}

// MARK: - Response Types

struct MCPanelResponse: Codable {
    let id: String
    let type: String
    let payload: AnyCodable
}

struct MCPanelEvent: Codable {
    let event: String
    let payload: AnyCodable?
}

// MARK: - Payload Types

struct BridgeReadyPayload: Codable {
    let version: String
    let platform: String
    let features: [String]
}

struct CompletionPayload: Codable {
    let completions: [Completion]
    let isAsync: Bool

    struct Completion: Codable {
        let text: String
        let tooltip: String?
    }
}

struct CommandTreePayload: Codable {
    let commands: [String: CommandNode]

    struct CommandNode: Codable {
        let description: String?
        let aliases: [String]?
        let permission: String?
        let usage: String?
        let children: [String: CommandNode]?
        let type: String?           // "literal" or argument type (e.g., "integer", "string", "player", "entity")
        let required: Bool?         // Whether this argument is required
        let examples: [String]?     // Example values for this argument

        /// Whether this node is an argument (vs a literal subcommand)
        var isArgument: Bool {
            type != nil && type != "literal"
        }
    }
}

struct PlayerListPayload: Codable {
    let count: Int
    let max: Int
    let players: [PlayerInfo]

    struct PlayerInfo: Codable {
        let name: String
        let uuid: String
        let world: String?
        let displayName: String?
        let health: Double
        let foodLevel: Int
        let ping: Int
        let op: Bool
        let gameMode: String?
    }
}

struct ServerStatusPayload: Codable {
    let version: String
    let software: String
    let softwareVersion: String?
    let onlinePlayers: Int
    let maxPlayers: Int
    let tps: [Double]?
    let mspt: Double?
    let memory: MemoryInfo
    let worlds: [WorldInfo]?

    struct MemoryInfo: Codable {
        let used: Int
        let max: Int
        let free: Int
    }

    struct WorldInfo: Codable {
        let name: String
        let players: Int
        let entities: Int
        let loadedChunks: Int
        let environment: String?
    }
}

struct PluginListPayload: Codable {
    let plugins: [PluginInfo]

    struct PluginInfo: Codable {
        let name: String
        let version: String
        let enabled: Bool
        let description: String?
        let authors: [String]?
        let website: String?
        let commands: [String]?
        let dependencies: [String]?
        let softDependencies: [String]?
    }
}

// MARK: - AnyCodable Helper

/// Type-erased Codable wrapper for dynamic JSON payloads
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable cannot encode value"))
        }
    }

    /// Try to decode as a specific type
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: value),
              let decoded = try? JSONDecoder().decode(type, from: jsonData) else {
            return nil
        }
        return decoded
    }
}
