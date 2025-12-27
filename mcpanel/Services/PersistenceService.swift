//
//  PersistenceService.swift
//  MCPanel
//
//  JSON-based persistence for server configurations
//

import Foundation

actor PersistenceService {
    private let serversFileName = "servers.json"

    private var appFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MCPanel", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return folder
    }

    private var serversURL: URL {
        appFolder.appendingPathComponent(serversFileName)
    }

    // MARK: - Servers

    func loadServers() async throws -> [Server] {
        guard FileManager.default.fileExists(atPath: serversURL.path) else {
            return []
        }

        let data = try Data(contentsOf: serversURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Server].self, from: data)
    }

    func saveServers(_ servers: [Server]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(servers)
        try data.write(to: serversURL, options: .atomic)
    }

    // MARK: - Command History

    func loadCommandHistory(for serverId: UUID) async throws -> CommandHistory {
        let historyURL = appFolder.appendingPathComponent("history_\(serverId.uuidString).json")

        guard FileManager.default.fileExists(atPath: historyURL.path) else {
            return CommandHistory()
        }

        let data = try Data(contentsOf: historyURL)
        return try JSONDecoder().decode(CommandHistory.self, from: data)
    }

    func saveCommandHistory(_ history: CommandHistory, for serverId: UUID) async throws {
        let historyURL = appFolder.appendingPathComponent("history_\(serverId.uuidString).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(history)
        try data.write(to: historyURL, options: .atomic)
    }
}
