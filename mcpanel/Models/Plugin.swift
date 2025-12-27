//
//  Plugin.swift
//  MCPanel
//
//  Model representing a Minecraft server plugin
//

import Foundation

struct Plugin: Identifiable, Hashable {
    let id: UUID
    var name: String
    var fileName: String      // e.g., "Oraxen-1.201.0.jar" or "SkinMotion.jar.disabled"
    var version: String?
    var description: String?
    var authors: [String]
    var isEnabled: Bool       // Derived from fileName (no .disabled extension)
    var fileSize: Int64
    var lastModified: Date?

    // MARK: - Computed Properties

    var displayName: String {
        // Remove version suffix if present in name
        name
    }

    var baseFileName: String {
        // Remove .disabled suffix if present
        if fileName.hasSuffix(".disabled") {
            return String(fileName.dropLast(".disabled".count))
        }
        return fileName
    }

    var disabledFileName: String {
        if fileName.hasSuffix(".disabled") {
            return fileName
        }
        return fileName + ".disabled"
    }

    var enabledFileName: String {
        if fileName.hasSuffix(".disabled") {
            return String(fileName.dropLast(".disabled".count))
        }
        return fileName
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var statusIcon: String {
        isEnabled ? "checkmark.circle.fill" : "xmark.circle"
    }

    var statusColor: String {
        isEnabled ? "22C55E" : "6B7280"
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        fileName: String,
        version: String? = nil,
        description: String? = nil,
        authors: [String] = [],
        fileSize: Int64 = 0,
        lastModified: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.version = version
        self.description = description
        self.authors = authors
        self.isEnabled = !fileName.hasSuffix(".disabled")
        self.fileSize = fileSize
        self.lastModified = lastModified
    }

    /// Create from a file listing line (ls -la output parsing)
    static func fromFileName(_ fileName: String, fileSize: Int64 = 0, lastModified: Date? = nil) -> Plugin? {
        // Only process .jar files (enabled or disabled)
        guard fileName.hasSuffix(".jar") || fileName.hasSuffix(".jar.disabled") else {
            return nil
        }

        // Skip backup files
        guard !fileName.contains(".bak") && !fileName.contains("-backup") else {
            return nil
        }

        // Extract name from fileName
        var baseName = fileName
        if baseName.hasSuffix(".disabled") {
            baseName = String(baseName.dropLast(".disabled".count))
        }
        if baseName.hasSuffix(".jar") {
            baseName = String(baseName.dropLast(".jar".count))
        }

        // Try to extract version (pattern: name-version or name_version)
        var name = baseName
        var version: String?

        // Common patterns: plugin-1.2.3, plugin_1.2.3, plugin-v1.2.3
        let versionPatterns = [
            #"-(\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z0-9]+)?)$"#,
            #"_(\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z0-9]+)?)$"#,
            #"-v(\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z0-9]+)?)$"#
        ]

        for pattern in versionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: baseName, range: NSRange(baseName.startIndex..., in: baseName)),
               let versionRange = Range(match.range(at: 1), in: baseName) {
                version = String(baseName[versionRange])
                // Remove version from name
                if let fullRange = Range(match.range(at: 0), in: baseName) {
                    name = String(baseName[..<fullRange.lowerBound])
                }
                break
            }
        }

        return Plugin(
            name: name,
            fileName: fileName,
            version: version,
            fileSize: fileSize,
            lastModified: lastModified
        )
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Plugin, rhs: Plugin) -> Bool {
        lhs.id == rhs.id
    }
}
