//
//  Server.swift
//  MCPanel
//
//  Model representing a remote Minecraft server
//

import Foundation

// MARK: - Server Status

enum ServerStatus: String, Codable {
    case online = "Online"
    case offline = "Offline"
    case starting = "Starting"
    case stopping = "Stopping"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .online: return "22C55E"    // Green
        case .offline: return "EF4444"   // Red
        case .starting, .stopping: return "EAB308" // Yellow
        case .unknown: return "6B7280"   // Gray
        }
    }
}

// MARK: - Authentication Method

enum AuthMethod: Codable, Hashable {
    case password
    case key(path: String)

    var displayName: String {
        switch self {
        case .password: return "Password"
        case .key: return "SSH Key"
        }
    }
}

// MARK: - Console Mode

enum ConsoleMode: String, Codable, CaseIterable, Identifiable {
    case logTail = "Log Tail"      // Traditional tail -f latest.log
    case ptyScreen = "Screen"      // PTY attached to screen session
    case ptyTmux = "Tmux"          // PTY attached to tmux session
    case ptyDirect = "Direct"      // Direct PTY shell
    case ptyMcwrap = "MCWrap"      // mcwrap session wrapper (recommended)

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .logTail: return "doc.text"
        case .ptyScreen: return "rectangle.split.3x1"
        case .ptyTmux: return "square.split.2x1"
        case .ptyDirect: return "terminal"
        case .ptyMcwrap: return "arrow.triangle.2.circlepath"
        }
    }

    var description: String {
        switch self {
        case .logTail: return "Read-only log streaming via tail -f"
        case .ptyScreen: return "Interactive console via GNU Screen"
        case .ptyTmux: return "Interactive console via tmux"
        case .ptyDirect: return "Direct PTY shell session"
        case .ptyMcwrap: return "mcwrap session (native scroll + truecolor)"
        }
    }

    var sessionType: SessionType? {
        switch self {
        case .logTail: return nil
        case .ptyScreen: return .screen
        case .ptyTmux: return .tmux
        case .ptyDirect: return .direct
        case .ptyMcwrap: return .mcwrap
        }
    }
}

// MARK: - Server Type

enum ServerType: String, Codable, CaseIterable, Identifiable {
    case vanilla = "Vanilla"
    case paper = "Paper"
    case purpur = "Purpur"
    case spigot = "Spigot"
    case fabric = "Fabric"
    case forge = "Forge"
    case velocity = "Velocity"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .vanilla: return "cube.fill"
        case .paper: return "doc.fill"
        case .purpur: return "sparkles"
        case .spigot: return "drop.fill"
        case .fabric: return "rectangle.grid.2x2.fill"
        case .forge: return "hammer.fill"
        case .velocity: return "bolt.fill"
        }
    }

    // API params for mcjarfiles.com
    var apiParams: (variant: String, category: String) {
        switch self {
        case .vanilla: return ("release", "vanilla")
        case .paper: return ("paper", "servers")
        case .purpur: return ("purpur", "servers")
        case .spigot: return ("spigot", "servers")
        case .fabric: return ("fabric", "modded")
        case .forge: return ("forge", "modded")
        case .velocity: return ("velocity", "proxies")
        }
    }
}

// MARK: - Server Model

struct Server: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var sshPort: Int
    var sshUsername: String
    var identityFilePath: String?  // Path to SSH key (nil = use password)
    var sshKeyBookmark: Data?      // Security-scoped bookmark for sandbox access to SSH key
    var serverPath: String         // e.g., /root/minecraft/paper-1.21
    var pluginsPath: String?       // e.g., /root/minecraft/paper-1.21/plugins
    var jarFileName: String        // e.g., paper.jar
    var rconHost: String?          // Usually 127.0.0.1 (from server perspective)
    var rconPort: Int?             // Default: 25575
    var rconPassword: String?      // RCON password from server.properties
    var screenSession: String?     // Screen session name, e.g., "minecraft"
    var tmuxSession: String?       // Tmux session name
    var systemdUnit: String?       // e.g., minecraft-test.service
    var serverType: ServerType
    var consoleMode: ConsoleMode   // How to connect to console (log tail, PTY/screen, etc.)
    var minecraftVersion: String?
    var dateAdded: Date

    // Transient state (not persisted)
    var status: ServerStatus = .unknown
    var playerCount: Int?
    var maxPlayers: Int?
    var lastChecked: Date?

    // MARK: - Computed Properties

    var authMethod: AuthMethod {
        if let keyPath = identityFilePath, !keyPath.isEmpty {
            return .key(path: keyPath)
        }
        return .password
    }

    var effectivePluginsPath: String {
        pluginsPath ?? "\(serverPath)/plugins"
    }

    var jarPath: String {
        "\(serverPath)/\(jarFileName)"
    }

    var statusDisplay: String {
        switch status {
        case .online:
            if let players = playerCount, let max = maxPlayers {
                return "\(players)/\(max) players"
            }
            return status.rawValue
        default:
            return status.rawValue
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        sshPort: Int = 22,
        sshUsername: String = "root",
        identityFilePath: String? = nil,
        sshKeyBookmark: Data? = nil,
        serverPath: String,
        pluginsPath: String? = nil,
        jarFileName: String = "server.jar",
        rconHost: String? = "127.0.0.1",
        rconPort: Int? = 25575,
        rconPassword: String? = nil,
        screenSession: String? = nil,
        tmuxSession: String? = nil,
        systemdUnit: String? = nil,
        serverType: ServerType = .paper,
        consoleMode: ConsoleMode = .logTail,
        minecraftVersion: String? = nil,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.identityFilePath = identityFilePath
        self.sshKeyBookmark = sshKeyBookmark
        self.serverPath = serverPath
        self.pluginsPath = pluginsPath
        self.jarFileName = jarFileName
        self.rconHost = rconHost
        self.rconPort = rconPort
        self.rconPassword = rconPassword
        self.screenSession = screenSession
        self.tmuxSession = tmuxSession
        self.systemdUnit = systemdUnit
        self.serverType = serverType
        self.consoleMode = consoleMode
        self.minecraftVersion = minecraftVersion
        self.dateAdded = dateAdded
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, host, sshPort, sshUsername, identityFilePath, sshKeyBookmark
        case serverPath, pluginsPath, jarFileName
        case rconHost, rconPort, rconPassword, screenSession, tmuxSession, systemdUnit
        case serverType, consoleMode, minecraftVersion, dateAdded
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Server, rhs: Server) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - SSH Key Access

    /// Resolve the SSH key path, using security-scoped bookmark if available
    /// Returns the path and a closure to stop accessing the resource when done
    func resolveSSHKeyPath() -> (path: String?, stopAccessing: () -> Void) {
        // Try to resolve from bookmark first (for sandbox access)
        if let bookmark = sshKeyBookmark {
            var isStale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    // Bookmark is stale (file moved/renamed/system updated)
                    // User will need to re-select SSH key in settings
                    print("[Server] SSH key bookmark is stale - please re-select your SSH key in server settings")
                }
                if url.startAccessingSecurityScopedResource() {
                    return (url.path, { url.stopAccessingSecurityScopedResource() })
                }
            } catch {
                print("[Server] Failed to resolve SSH key bookmark: \(error)")
            }
        }

        // Fall back to direct path (works outside sandbox or for system SSH keys)
        if let path = identityFilePath, !path.isEmpty {
            let expandedPath = NSString(string: path).expandingTildeInPath
            return (expandedPath, { })
        }

        return (nil, { })
    }

    /// Create a security-scoped bookmark for an SSH key file
    static func createSSHKeyBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            print("[Server] Failed to create SSH key bookmark: \(error)")
            return nil
        }
    }
}

// MARK: - Server Stats

struct ServerStats: Codable {
    var cpuUsage: Double?
    var memoryUsed: Int64?
    var memoryTotal: Int64?
    var uptime: TimeInterval?
    var tps: Double?  // Ticks per second (Minecraft performance metric)

    var memoryUsageString: String? {
        guard let used = memoryUsed, let total = memoryTotal else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return "\(formatter.string(fromByteCount: used)) / \(formatter.string(fromByteCount: total))"
    }
}
