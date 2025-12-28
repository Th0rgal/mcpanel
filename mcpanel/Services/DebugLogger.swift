//
//  DebugLogger.swift
//  MCPanel
//
//  Debug logging service for command completion and bridge features
//

import Foundation

/// Centralized debug logger that writes to both console and file
/// Enable verbose logging by setting MCPANEL_DEBUG=1 environment variable
/// or by calling DebugLogger.shared.setVerbose(true)
class DebugLogger {
    static let shared = DebugLogger()

    private let logFileURL: URL
    private let queue = DispatchQueue(label: "md.thomas.mcpanel.debug-logger", qos: .utility)
    private var isVerbose: Bool
    private let dateFormatter: DateFormatter

    private init() {
        // Create log directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logDir = appSupport.appendingPathComponent("MCPanel/debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // Create log file with date
        let dateStr = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        logFileURL = logDir.appendingPathComponent("mcpanel-debug-\(dateStr).log")

        // Check environment variable
        isVerbose = ProcessInfo.processInfo.environment["MCPANEL_DEBUG"] == "1"

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"

        // Log startup
        log("=== MCPanel Debug Logger Started ===", category: .system)
        log("Log file: \(logFileURL.path)", category: .system)
        log("Verbose mode: \(isVerbose)", category: .system)
    }

    enum Category: String {
        case system = "SYS"
        case bridge = "BRIDGE"
        case commands = "CMDS"
        case ssh = "SSH"
        case ui = "UI"
        case pty = "PTY"
    }

    func setVerbose(_ verbose: Bool) {
        isVerbose = verbose
        log("Verbose mode set to: \(verbose)", category: .system)
    }

    func log(_ message: String, category: Category, verbose: Bool = false) {
        // Skip verbose messages if not in verbose mode
        if verbose && !isVerbose { return }

        let timestamp = dateFormatter.string(from: Date())
        let formattedMessage = "[\(timestamp)] [\(category.rawValue)] \(message)"

        // Print to console
        print(formattedMessage)

        // Write to file asynchronously
        queue.async { [weak self] in
            guard let self else { return }
            let data = (formattedMessage + "\n").data(using: .utf8) ?? Data()

            if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: self.logFileURL)
            }
        }
    }

    /// Get the path to the current log file
    var logFilePath: String {
        logFileURL.path
    }

    /// Get recent log entries (last N lines)
    func recentLogs(lines: Int = 100) -> String {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return "No logs available"
        }
        let allLines = content.components(separatedBy: .newlines)
        let recent = allLines.suffix(lines)
        return recent.joined(separator: "\n")
    }

    /// Export full debug state as JSON
    @MainActor
    func exportDebugState(serverManager: ServerManager) -> String {
        var state: [String: Any] = [:]

        // Command trees per server
        var commandTrees: [String: Any] = [:]
        for (serverId, tree) in serverManager.commandTree {
            commandTrees[serverId.uuidString] = [
                "rootCommandCount": tree.rootCommands.count,
                "rootCommands": Array(tree.rootCommands).sorted().prefix(50),
                "subcommandCount": tree.subcommands.count
            ]
        }
        state["commandTrees"] = commandTrees

        // Bridge services state
        var bridgeStates: [String: Any] = [:]
        for (serverId, bridge) in serverManager.bridgeServices {
            bridgeStates[serverId.uuidString] = [
                "bridgeDetected": bridge.bridgeDetected,
                "hasCommandTree": bridge.commandTree != nil,
                "commandCount": bridge.commandTree?.commands.count ?? 0
            ]
        }
        state["bridgeServices"] = bridgeStates

        // General state
        state["commandTreeUpdateCount"] = serverManager.commandTreeUpdateCount
        state["serverCount"] = serverManager.servers.count
        state["timestamp"] = ISO8601DateFormatter().string(from: Date())

        if let jsonData = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
}

// MARK: - Convenience Extensions

extension DebugLogger {
    /// Log command tree fetch attempt
    func logCommandTreeFetch(serverPath: String, method: String) {
        log("Fetching commands.json via \(method) from: \(serverPath)", category: .commands)
    }

    /// Log command tree result
    func logCommandTreeResult(commandCount: Int, source: String) {
        log("Loaded \(commandCount) commands from \(source)", category: .commands)
    }

    /// Log command tree failure
    func logCommandTreeError(_ error: Error, source: String) {
        log("Failed to load commands from \(source): \(error.localizedDescription)", category: .commands)
    }

    /// Log SSH command execution
    func logSSHCommand(_ command: String, truncate: Int = 200) {
        let truncated = command.prefix(truncate)
        log("Executing: \(truncated)\(command.count > truncate ? "..." : "")", category: .ssh, verbose: true)
    }

    /// Log SSH result
    func logSSHResult(_ output: String, truncate: Int = 500) {
        let truncated = output.prefix(truncate)
        log("Result (\(output.count) bytes): \(truncated)\(output.count > truncate ? "..." : "")", category: .ssh, verbose: true)
    }

    /// Log bridge detection
    func logBridgeDetection(detected: Bool, reason: String) {
        log("Bridge detection: \(detected) (\(reason))", category: .bridge)
    }

    /// Log UI autocomplete request
    func logAutocomplete(prefix: String, resultCount: Int) {
        log("Autocomplete for '\(prefix)': \(resultCount) suggestions", category: .ui, verbose: true)
    }
}
