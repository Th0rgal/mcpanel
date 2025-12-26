//
//  FileItem.swift
//  MCPanel
//
//  Model representing a file or directory on the remote server
//

import Foundation

struct FileItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64
    var permissions: String?
    var owner: String?
    var group: String?
    var lastModified: Date?

    // MARK: - Computed Properties

    var formattedSize: String {
        guard !isDirectory else { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }

        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jar":
            return "shippingbox.fill"
        case "yml", "yaml":
            return "doc.text.fill"
        case "json":
            return "curlybraces"
        case "properties":
            return "gearshape.fill"
        case "log", "txt":
            return "doc.plaintext.fill"
        case "zip", "tar", "gz":
            return "doc.zipper"
        case "png", "jpg", "jpeg", "gif", "webp":
            return "photo.fill"
        case "sk":  // Skript files
            return "scroll.fill"
        case "db", "sqlite":
            return "cylinder.fill"
        default:
            return "doc.fill"
        }
    }

    var iconColor: String {
        if isDirectory {
            return "3B82F6"  // Blue
        }

        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jar":
            return "F97316"  // Orange
        case "yml", "yaml":
            return "A855F7"  // Purple
        case "json":
            return "EAB308"  // Yellow
        case "properties":
            return "6B7280"  // Gray
        case "log":
            return "22C55E"  // Green
        default:
            return "9CA3AF"  // Light gray
        }
    }

    var isHidden: Bool {
        name.hasPrefix(".")
    }

    var isJar: Bool {
        name.hasSuffix(".jar") || name.hasSuffix(".jar.disabled")
    }

    var isConfig: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["yml", "yaml", "json", "properties", "toml", "conf"].contains(ext)
    }

    var formattedDate: String {
        guard let date = lastModified else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        isDirectory: Bool = false,
        size: Int64 = 0,
        permissions: String? = nil,
        owner: String? = nil,
        group: String? = nil,
        lastModified: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.permissions = permissions
        self.owner = owner
        self.group = group
        self.lastModified = lastModified
    }

    /// Parse from ls -la output line
    /// Format: drwxr-xr-x 10 root root 4096 Dec 26 09:57 plugins
    static func parse(line: String, parentPath: String) -> FileItem? {
        let components = line.split(separator: " ", omittingEmptySubsequences: true)
        guard components.count >= 9 else { return nil }

        let permissions = String(components[0])
        let owner = String(components[2])
        let group = String(components[3])
        let size = Int64(components[4]) ?? 0

        // Parse date (components 5, 6, 7 or 5, 6)
        // Format varies: "Dec 26 09:57" or "Dec 26 2024"
        var nameStartIndex = 8
        var dateStr = "\(components[5]) \(components[6]) \(components[7])"

        // The name is everything after the date
        let name = components[nameStartIndex...].joined(separator: " ")

        // Skip . and ..
        guard name != "." && name != ".." else { return nil }

        // Parse date
        var lastModified: Date?
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Try "MMM dd HH:mm" format first (recent files)
        dateFormatter.dateFormat = "MMM dd HH:mm"
        if let date = dateFormatter.date(from: dateStr) {
            // Add current year
            let calendar = Calendar.current
            var components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            components.year = calendar.component(.year, from: Date())
            lastModified = calendar.date(from: components)
        } else {
            // Try "MMM dd yyyy" format (older files)
            dateFormatter.dateFormat = "MMM dd yyyy"
            lastModified = dateFormatter.date(from: dateStr)
        }

        let isDirectory = permissions.hasPrefix("d")
        let path = parentPath.hasSuffix("/") ? parentPath + name : parentPath + "/" + name

        return FileItem(
            name: name,
            path: path,
            isDirectory: isDirectory,
            size: size,
            permissions: permissions,
            owner: owner,
            group: group,
            lastModified: lastModified
        )
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
}
