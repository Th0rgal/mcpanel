//
//  ServerPropertiesView.swift
//  MCPanel
//
//  Editor for server.properties with Minecraft formatting preview
//

import SwiftUI

// MARK: - Server Property Model

struct ServerProperty: Identifiable {
    let id = UUID()
    var key: String
    var value: String
    var comment: String?

    // Known property descriptions
    static let descriptions: [String: String] = [
        "motd": "Message displayed in the server list",
        "server-port": "Port the server listens on",
        "max-players": "Maximum number of players",
        "difficulty": "Game difficulty (peaceful, easy, normal, hard)",
        "gamemode": "Default game mode (survival, creative, adventure, spectator)",
        "level-name": "Name of the world folder",
        "level-seed": "World generation seed",
        "pvp": "Allow player vs player combat",
        "spawn-protection": "Radius of spawn protection",
        "view-distance": "Maximum view distance in chunks",
        "simulation-distance": "Maximum simulation distance in chunks",
        "online-mode": "Verify players with Minecraft servers",
        "white-list": "Only allow whitelisted players",
        "enforce-whitelist": "Kick non-whitelisted players when enabled",
        "spawn-monsters": "Allow monster spawning",
        "spawn-animals": "Allow animal spawning",
        "spawn-npcs": "Allow villager spawning",
        "allow-flight": "Allow flight in survival mode",
        "allow-nether": "Allow nether portal travel",
        "enable-command-block": "Enable command blocks",
        "op-permission-level": "Default OP permission level (1-4)",
        "hardcore": "Enable hardcore mode (permadeath)",
        "enable-rcon": "Enable remote console",
        "rcon.port": "RCON port number",
        "rcon.password": "RCON password",
        "query.port": "Query protocol port",
        "enable-query": "Enable GameSpy4 query protocol",
        "server-ip": "IP address to bind to (leave blank for all)",
        "network-compression-threshold": "Packet compression threshold",
        "max-tick-time": "Maximum tick time before watchdog kills server",
        "sync-chunk-writes": "Synchronous chunk writes",
        "enable-jmx-monitoring": "Enable JMX monitoring",
        "enable-status": "Show server in server list",
        "entity-broadcast-range-percentage": "Entity visibility range percentage",
        "function-permission-level": "Permission level for functions",
        "rate-limit": "Packet rate limit per connection",
        "text-filtering-config": "Text filtering configuration file",
        "prevent-proxy-connections": "Block proxy/VPN connections",
        "resource-pack": "URL to resource pack",
        "resource-pack-prompt": "Resource pack prompt message",
        "resource-pack-sha1": "Resource pack SHA-1 hash",
        "require-resource-pack": "Require resource pack to join"
    ]

    var description: String? {
        ServerProperty.descriptions[key]
    }

    var isBooleanProperty: Bool {
        ["true", "false"].contains(value.lowercased())
    }

    var boolValue: Bool {
        get { value.lowercased() == "true" }
        set { value = newValue ? "true" : "false" }
    }
}

// MARK: - Server Properties View

struct ServerPropertiesView: View {
    @EnvironmentObject var serverManager: ServerManager
    let server: Server

    @State private var properties: [ServerProperty] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var searchText = ""
    @State private var hasChanges = false
    @State private var errorMessage: String?
    @State private var showMotdPreview = false

    var filteredProperties: [ServerProperty] {
        guard !searchText.isEmpty else { return properties }
        return properties.filter {
            $0.key.localizedCaseInsensitiveContains(searchText) ||
            $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    var motdProperty: Binding<ServerProperty>? {
        guard let index = properties.firstIndex(where: { $0.key == "motd" }) else { return nil }
        return Binding(
            get: { properties[index] },
            set: { properties[index] = $0; hasChanges = true }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            if isLoading {
                Spacer()
                ProgressView("Loading server.properties...")
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.white.opacity(0.6))
                    GlassButton(title: "Retry", icon: "arrow.clockwise", style: .secondary) {
                        Task { await loadProperties() }
                    }
                }
                Spacer()
            } else {
                // Properties list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // MOTD Preview section (if motd exists)
                        if let motd = motdProperty {
                            MotdSection(property: motd, isExpanded: $showMotdPreview)
                                .padding(.horizontal, 24)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                        }

                        // Properties
                        ForEach(filteredProperties) { property in
                            if property.key != "motd" {
                                PropertyRow(
                                    property: binding(for: property),
                                    onChanged: { hasChanges = true }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .onAppear {
            Task { await loadProperties() }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.4))
                    .font(.system(size: 12))

                TextField("Search properties...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.4))
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .frame(maxWidth: 300)

            Spacer()

            // Property count
            Text("\(filteredProperties.count) properties")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))

            // Reload button
            GlassIconButton(icon: "arrow.clockwise") {
                Task { await loadProperties() }
            }
            .disabled(isLoading)

            // Save button
            if hasChanges {
                GlassButton(title: "Save", icon: "square.and.arrow.down", style: .primary) {
                    Task { await saveProperties() }
                }
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(Color(hex: "161618").opacity(0.8))
        }
    }

    // MARK: - Helpers

    private func binding(for property: ServerProperty) -> Binding<ServerProperty> {
        guard let index = properties.firstIndex(where: { $0.id == property.id }) else {
            return .constant(property)
        }
        return Binding(
            get: { properties[index] },
            set: { properties[index] = $0 }
        )
    }

    private func loadProperties() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let ssh = serverManager.sshService(for: server)
        let propertiesPath = "\(server.serverPath)/server.properties"

        do {
            let content = try await ssh.execute("cat '\(propertiesPath)'")
            properties = parseProperties(content)
            hasChanges = false
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func saveProperties() async {
        isSaving = true
        defer { isSaving = false }

        let ssh = serverManager.sshService(for: server)
        let propertiesPath = "\(server.serverPath)/server.properties"

        // Build content with comments preserved
        var lines: [String] = []
        for property in properties {
            if let comment = property.comment {
                lines.append(comment)
            }
            lines.append("\(property.key)=\(property.value)")
        }
        let content = lines.joined(separator: "\n")

        // Escape for shell
        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")

        let command = "printf \"%s\" \"\(escapedContent)\" > '\(propertiesPath)'"

        do {
            _ = try await ssh.execute(command)
            hasChanges = false
        } catch {
            serverManager.errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    private func parseProperties(_ content: String) -> [ServerProperty] {
        var result: [ServerProperty] = []
        var pendingComment: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                pendingComment = line
                continue
            }

            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count >= 1 else { continue }

            let key = String(parts[0])
            let value = parts.count > 1 ? String(parts[1]) : ""

            result.append(ServerProperty(
                key: key,
                value: value,
                comment: pendingComment
            ))
            pendingComment = nil
        }

        return result
    }
}

// MARK: - MOTD Section with Preview

struct MotdSection: View {
    @Binding var property: ServerProperty
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 14))

                Text("MOTD (Message of the Day)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            // Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .textCase(.uppercase)

                MinecraftFormattedText(text: property.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.black.opacity(0.4))
                    }
            }

            // Editor (expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edit MOTD")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .textCase(.uppercase)

                    TextEditor(text: $property.value)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 60)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                }
                        }

                    // Formatting help
                    DisclosureGroup("Formatting Codes") {
                        MinecraftFormattingHelp()
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - Minecraft Formatted Text

struct MinecraftFormattedText: View {
    let text: String

    var body: some View {
        Text(parseMinecraftFormatting(text))
            .font(.system(size: 14, design: .monospaced))
    }

    private func parseMinecraftFormatting(_ input: String) -> AttributedString {
        var result = AttributedString()

        // First, convert escaped newlines (\n) to actual newlines
        // In server.properties, newlines are stored as literal backslash-n
        let processedInput = input.replacingOccurrences(of: "\\n", with: "\n")

        // Minecraft color codes
        let colors: [Character: Color] = [
            "0": Color(hex: "000000"), // Black
            "1": Color(hex: "0000AA"), // Dark Blue
            "2": Color(hex: "00AA00"), // Dark Green
            "3": Color(hex: "00AAAA"), // Dark Aqua
            "4": Color(hex: "AA0000"), // Dark Red
            "5": Color(hex: "AA00AA"), // Dark Purple
            "6": Color(hex: "FFAA00"), // Gold
            "7": Color(hex: "AAAAAA"), // Gray
            "8": Color(hex: "555555"), // Dark Gray
            "9": Color(hex: "5555FF"), // Blue
            "a": Color(hex: "55FF55"), // Green
            "b": Color(hex: "55FFFF"), // Aqua
            "c": Color(hex: "FF5555"), // Red
            "d": Color(hex: "FF55FF"), // Light Purple
            "e": Color(hex: "FFFF55"), // Yellow
            "f": Color(hex: "FFFFFF")  // White
        ]

        var currentColor: Color = .white
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrikethrough = false
        var _isObfuscated = false  // Not rendered visually, but parsed for completeness

        var currentText = ""
        var i = processedInput.startIndex

        while i < processedInput.endIndex {
            let char = processedInput[i]

            // Check for § or & formatting codes
            if (char == "§" || char == "&") && processedInput.index(after: i) < processedInput.endIndex {
                // Flush current text
                if !currentText.isEmpty {
                    var attr = AttributedString(currentText)
                    attr.foregroundColor = currentColor
                    if isBold { attr.font = .system(size: 14, weight: .bold, design: .monospaced) }
                    if isItalic { attr.font = (attr.font ?? .system(size: 14, design: .monospaced)).italic() }
                    if isUnderline { attr.underlineStyle = .single }
                    if isStrikethrough { attr.strikethroughStyle = .single }
                    result.append(attr)
                    currentText = ""
                }

                let codeIndex = processedInput.index(after: i)
                let code = processedInput[codeIndex].lowercased().first!

                if let color = colors[code] {
                    currentColor = color
                    // Reset formatting on color change
                    isBold = false
                    isItalic = false
                    isUnderline = false
                    isStrikethrough = false
                    _isObfuscated = false
                } else {
                    switch code {
                    case "l": isBold = true
                    case "o": isItalic = true
                    case "n": isUnderline = true
                    case "m": isStrikethrough = true
                    case "k": _isObfuscated = true
                    case "r": // Reset
                        currentColor = .white
                        isBold = false
                        isItalic = false
                        isUnderline = false
                        isStrikethrough = false
                        _isObfuscated = false
                    default: break
                    }
                }

                i = processedInput.index(after: codeIndex)
            } else {
                currentText.append(char)
                i = processedInput.index(after: i)
            }
        }

        // Flush remaining text
        if !currentText.isEmpty {
            var attr = AttributedString(currentText)
            attr.foregroundColor = currentColor
            if isBold { attr.font = .system(size: 14, weight: .bold, design: .monospaced) }
            if isItalic { attr.font = (attr.font ?? .system(size: 14, design: .monospaced)).italic() }
            if isUnderline { attr.underlineStyle = .single }
            if isStrikethrough { attr.strikethroughStyle = .single }
            result.append(attr)
        }

        return result
    }
}

// MARK: - Minecraft Formatting Help

struct MinecraftFormattingHelp: View {
    let codes: [(String, String, Color?)] = [
        ("§0", "Black", Color(hex: "000000")),
        ("§1", "Dark Blue", Color(hex: "0000AA")),
        ("§2", "Dark Green", Color(hex: "00AA00")),
        ("§3", "Dark Aqua", Color(hex: "00AAAA")),
        ("§4", "Dark Red", Color(hex: "AA0000")),
        ("§5", "Dark Purple", Color(hex: "AA00AA")),
        ("§6", "Gold", Color(hex: "FFAA00")),
        ("§7", "Gray", Color(hex: "AAAAAA")),
        ("§8", "Dark Gray", Color(hex: "555555")),
        ("§9", "Blue", Color(hex: "5555FF")),
        ("§a", "Green", Color(hex: "55FF55")),
        ("§b", "Aqua", Color(hex: "55FFFF")),
        ("§c", "Red", Color(hex: "FF5555")),
        ("§d", "Light Purple", Color(hex: "FF55FF")),
        ("§e", "Yellow", Color(hex: "FFFF55")),
        ("§f", "White", Color(hex: "FFFFFF")),
        ("§l", "Bold", nil),
        ("§o", "Italic", nil),
        ("§n", "Underline", nil),
        ("§m", "Strikethrough", nil),
        ("§r", "Reset", nil)
    ]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(codes, id: \.0) { code, name, color in
                HStack(spacing: 6) {
                    Text(code)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    if let color = color {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                    }

                    Text(name)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Property Row

struct PropertyRow: View {
    @Binding var property: ServerProperty
    var onChanged: () -> Void

    @State private var isEditing = false
    @State private var editValue: String = ""

    var body: some View {
        HStack(spacing: 12) {
            // Key
            VStack(alignment: .leading, spacing: 2) {
                Text(property.key)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)

                if let desc = property.description {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 200, alignment: .leading)

            Spacer()

            // Value editor
            if property.isBooleanProperty {
                Toggle("", isOn: Binding(
                    get: { property.boolValue },
                    set: {
                        property.value = $0 ? "true" : "false"
                        onChanged()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            } else if isEditing {
                TextField("", text: $editValue, onCommit: {
                    property.value = editValue
                    onChanged()
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 200)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        }
                }
                .onAppear { editValue = property.value }
            } else {
                Button {
                    editValue = property.value
                    isEditing = true
                } label: {
                    Text(property.value.isEmpty ? "(empty)" : property.value)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(property.value.isEmpty ? .white.opacity(0.3) : .white.opacity(0.8))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 200, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(Color.white.opacity(0.02))
        }
    }
}
