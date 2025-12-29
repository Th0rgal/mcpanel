//
//  PersistenceService.swift
//  MCPanel
//
//  JSON-based persistence for server configurations
//

import Foundation

actor PersistenceService {
    private let serversFileName = "servers.json"
    // Thread-safe migration flag using OSAtomicCompareAndSwapInt
    private static let migrationLock = NSLock()
    private static var _hasMigrated = false
    private static var hasMigrated: Bool {
        get {
            migrationLock.lock()
            defer { migrationLock.unlock() }
            return _hasMigrated
        }
        set {
            migrationLock.lock()
            defer { migrationLock.unlock() }
            _hasMigrated = newValue
        }
    }

    private var appFolder: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("MCPanel", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return folder
    }

    // MARK: - Data Migration

    /// Migrate data from pre-sandbox location if needed
    /// When sandbox is enabled, Application Support moves from:
    /// ~/Library/Application Support/MCPanel/ to
    /// ~/Library/Containers/<bundle-id>/Data/Library/Application Support/MCPanel/
    private func migrateDataIfNeeded() {
        guard !Self.hasMigrated else { return }
        Self.hasMigrated = true

        let fm = FileManager.default

        // Check if we're in a sandbox container
        let currentPath = appFolder.path
        guard currentPath.contains("/Containers/") else {
            // Not sandboxed, no migration needed
            return
        }

        // Construct the old pre-sandbox path
        let homeDir = fm.homeDirectoryForCurrentUser.path
        // In sandbox, homeDir points to container, so we need to go up
        // ~/Library/Containers/<bundle-id>/Data -> extract the real home
        if let range = homeDir.range(of: "/Library/Containers/") {
            let realHome = String(homeDir[..<range.lowerBound])
            let oldFolder = "\(realHome)/Library/Application Support/MCPanel"

            guard fm.fileExists(atPath: oldFolder) else {
                // No old data to migrate
                return
            }

            // Check if new location already has data (don't overwrite)
            let newServersFile = appFolder.appendingPathComponent(serversFileName).path
            if fm.fileExists(atPath: newServersFile) {
                // Already have data in new location, skip migration
                return
            }

            // Migrate files from old location
            do {
                let oldFolderURL = URL(fileURLWithPath: oldFolder)
                let contents = try fm.contentsOfDirectory(at: oldFolderURL, includingPropertiesForKeys: nil)

                for file in contents {
                    let destURL = appFolder.appendingPathComponent(file.lastPathComponent)
                    if !fm.fileExists(atPath: destURL.path) {
                        try fm.copyItem(at: file, to: destURL)
                    }
                }

                print("[PersistenceService] Migrated data from pre-sandbox location")
            } catch {
                print("[PersistenceService] Migration failed: \(error)")
            }
        }
    }

    private var serversURL: URL {
        appFolder.appendingPathComponent(serversFileName)
    }

    // MARK: - Servers

    func loadServers() async throws -> [Server] {
        // Attempt to migrate data from pre-sandbox location on first load
        migrateDataIfNeeded()

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
