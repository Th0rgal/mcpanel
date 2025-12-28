//
//  ServerPropertiesView.swift
//  MCPanel
//
//  Premium editor for server.properties with categorized layout and smart inputs
//

import SwiftUI

// MARK: - Property Metadata System

/// Categories for organizing server properties
enum PropertyCategory: String, CaseIterable, Identifiable {
    case serverBasics = "Server Basics"
    case gameplay = "Gameplay"
    case world = "World"
    case security = "Security"
    case network = "Network"
    case administration = "Administration"
    case performance = "Performance"
    case resourcePack = "Resource Pack"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .serverBasics: return "server.rack"
        case .gameplay: return "gamecontroller.fill"
        case .world: return "globe.americas.fill"
        case .security: return "lock.shield.fill"
        case .network: return "network"
        case .administration: return "gearshape.2.fill"
        case .performance: return "gauge.with.needle.fill"
        case .resourcePack: return "shippingbox.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .serverBasics: return PremiumColors.indigo
        case .gameplay: return PremiumColors.emerald
        case .world: return PremiumColors.teal
        case .security: return PremiumColors.rose
        case .network: return PremiumColors.sky
        case .administration: return PremiumColors.violet
        case .performance: return PremiumColors.amber
        case .resourcePack: return Color(hex: "EC4899") // Pink
        case .other: return PremiumColors.slate
        }
    }
}

/// Input type for property values
enum PropertyInputType {
    case boolean
    case integer(min: Int?, max: Int?, unit: String?)
    case text
    case multilineText
    case enumeration([String])
    case port
    case password
}

/// Metadata for a known server property
struct PropertyMetadata {
    let key: String
    let displayName: String
    let description: String
    let category: PropertyCategory
    let inputType: PropertyInputType
    let defaultValue: String?
    let isAdvanced: Bool

    init(
        key: String,
        displayName: String,
        description: String,
        category: PropertyCategory,
        inputType: PropertyInputType = .text,
        defaultValue: String? = nil,
        isAdvanced: Bool = false
    ) {
        self.key = key
        self.displayName = displayName
        self.description = description
        self.category = category
        self.inputType = inputType
        self.defaultValue = defaultValue
        self.isAdvanced = isAdvanced
    }
}

/// Registry of all known Minecraft server properties
enum PropertyRegistry {
    static let properties: [String: PropertyMetadata] = {
        var dict: [String: PropertyMetadata] = [:]
        for prop in allProperties {
            dict[prop.key] = prop
        }
        return dict
    }()

    static let allProperties: [PropertyMetadata] = [
        // Server Basics
        PropertyMetadata(
            key: "motd",
            displayName: "Message of the Day",
            description: "Message displayed in the server list. Supports Minecraft color codes.",
            category: .serverBasics,
            inputType: .multilineText,
            defaultValue: "A Minecraft Server"
        ),
        PropertyMetadata(
            key: "server-port",
            displayName: "Server Port",
            description: "Port the server listens on for connections.",
            category: .serverBasics,
            inputType: .port,
            defaultValue: "25565"
        ),
        PropertyMetadata(
            key: "max-players",
            displayName: "Max Players",
            description: "Maximum number of players that can join simultaneously.",
            category: .serverBasics,
            inputType: .integer(min: 1, max: 1000, unit: "players"),
            defaultValue: "20"
        ),
        PropertyMetadata(
            key: "level-name",
            displayName: "World Name",
            description: "Name of the world folder.",
            category: .serverBasics,
            inputType: .text,
            defaultValue: "world"
        ),
        PropertyMetadata(
            key: "server-ip",
            displayName: "Server IP",
            description: "IP address to bind to. Leave blank to bind to all interfaces.",
            category: .serverBasics,
            inputType: .text,
            defaultValue: ""
        ),
        PropertyMetadata(
            key: "enable-status",
            displayName: "Show in Server List",
            description: "Whether the server appears in the server list.",
            category: .serverBasics,
            inputType: .boolean,
            defaultValue: "true"
        ),

        // Gameplay
        PropertyMetadata(
            key: "difficulty",
            displayName: "Difficulty",
            description: "Game difficulty level.",
            category: .gameplay,
            inputType: .enumeration(["peaceful", "easy", "normal", "hard"]),
            defaultValue: "easy"
        ),
        PropertyMetadata(
            key: "gamemode",
            displayName: "Default Gamemode",
            description: "Default game mode for new players.",
            category: .gameplay,
            inputType: .enumeration(["survival", "creative", "adventure", "spectator"]),
            defaultValue: "survival"
        ),
        PropertyMetadata(
            key: "force-gamemode",
            displayName: "Force Gamemode",
            description: "Force players to join in the default game mode.",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "pvp",
            displayName: "PvP Combat",
            description: "Allow players to fight each other.",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "hardcore",
            displayName: "Hardcore Mode",
            description: "Enable hardcore mode (permadeath).",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "allow-flight",
            displayName: "Allow Flight",
            description: "Allow flight in survival mode (requires client mod).",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "allow-nether",
            displayName: "Allow Nether",
            description: "Allow players to travel to the Nether.",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "spawn-monsters",
            displayName: "Spawn Monsters",
            description: "Allow hostile mobs to spawn.",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "spawn-animals",
            displayName: "Spawn Animals",
            description: "Allow animals to spawn.",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "spawn-npcs",
            displayName: "Spawn Villagers",
            description: "Allow villagers to spawn.",
            category: .gameplay,
            inputType: .boolean,
            defaultValue: "true"
        ),

        // World
        PropertyMetadata(
            key: "level-seed",
            displayName: "World Seed",
            description: "Seed for world generation. Leave blank for random.",
            category: .world,
            inputType: .text,
            defaultValue: ""
        ),
        PropertyMetadata(
            key: "level-type",
            displayName: "World Type",
            description: "Type of world to generate.",
            category: .world,
            inputType: .enumeration(["minecraft:normal", "minecraft:flat", "minecraft:large_biomes", "minecraft:amplified", "minecraft:single_biome_surface"]),
            defaultValue: "minecraft:normal"
        ),
        PropertyMetadata(
            key: "view-distance",
            displayName: "View Distance",
            description: "Maximum view distance in chunks.",
            category: .world,
            inputType: .integer(min: 3, max: 32, unit: "chunks"),
            defaultValue: "10"
        ),
        PropertyMetadata(
            key: "simulation-distance",
            displayName: "Simulation Distance",
            description: "Maximum simulation distance in chunks.",
            category: .world,
            inputType: .integer(min: 3, max: 32, unit: "chunks"),
            defaultValue: "10"
        ),
        PropertyMetadata(
            key: "spawn-protection",
            displayName: "Spawn Protection",
            description: "Radius of spawn protection (0 to disable).",
            category: .world,
            inputType: .integer(min: 0, max: 256, unit: "blocks"),
            defaultValue: "16"
        ),
        PropertyMetadata(
            key: "max-world-size",
            displayName: "Max World Size",
            description: "Maximum world radius in blocks.",
            category: .world,
            inputType: .integer(min: 1, max: 29999984, unit: "blocks"),
            defaultValue: "29999984",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "generate-structures",
            displayName: "Generate Structures",
            description: "Generate structures like villages and temples.",
            category: .world,
            inputType: .boolean,
            defaultValue: "true"
        ),

        // Security
        PropertyMetadata(
            key: "online-mode",
            displayName: "Online Mode",
            description: "Verify players with Minecraft authentication servers. Disable for offline/cracked servers.",
            category: .security,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "white-list",
            displayName: "Whitelist",
            description: "Only allow whitelisted players to join.",
            category: .security,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "enforce-whitelist",
            displayName: "Enforce Whitelist",
            description: "Kick non-whitelisted players when whitelist is enabled.",
            category: .security,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "prevent-proxy-connections",
            displayName: "Block Proxy/VPN",
            description: "Block connections from proxy and VPN services.",
            category: .security,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "enforce-secure-profile",
            displayName: "Enforce Secure Profile",
            description: "Require players to have a Mojang-signed public key.",
            category: .security,
            inputType: .boolean,
            defaultValue: "true"
        ),

        // Network
        PropertyMetadata(
            key: "network-compression-threshold",
            displayName: "Compression Threshold",
            description: "Packet size threshold for compression (-1 to disable).",
            category: .network,
            inputType: .integer(min: -1, max: 65535, unit: "bytes"),
            defaultValue: "256",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "rate-limit",
            displayName: "Rate Limit",
            description: "Maximum packets per second per connection (0 to disable).",
            category: .network,
            inputType: .integer(min: 0, max: 10000, unit: "packets/sec"),
            defaultValue: "0",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "enable-query",
            displayName: "Enable Query",
            description: "Enable GameSpy4 query protocol for server info.",
            category: .network,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "query.port",
            displayName: "Query Port",
            description: "Port for the query protocol.",
            category: .network,
            inputType: .port,
            defaultValue: "25565"
        ),
        PropertyMetadata(
            key: "accepts-transfers",
            displayName: "Accept Transfers",
            description: "Accept player transfers from other servers.",
            category: .network,
            inputType: .boolean,
            defaultValue: "false"
        ),

        // Administration
        PropertyMetadata(
            key: "enable-rcon",
            displayName: "Enable RCON",
            description: "Enable remote console access.",
            category: .administration,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "rcon.port",
            displayName: "RCON Port",
            description: "Port for RCON connections.",
            category: .administration,
            inputType: .port,
            defaultValue: "25575"
        ),
        PropertyMetadata(
            key: "rcon.password",
            displayName: "RCON Password",
            description: "Password for RCON authentication.",
            category: .administration,
            inputType: .password,
            defaultValue: ""
        ),
        PropertyMetadata(
            key: "broadcast-rcon-to-ops",
            displayName: "Broadcast RCON to Ops",
            description: "Show RCON command output to operators.",
            category: .administration,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "broadcast-console-to-ops",
            displayName: "Broadcast Console to Ops",
            description: "Show console command output to operators.",
            category: .administration,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "op-permission-level",
            displayName: "Op Permission Level",
            description: "Default permission level for operators (1-4).",
            category: .administration,
            inputType: .integer(min: 1, max: 4, unit: nil),
            defaultValue: "4"
        ),
        PropertyMetadata(
            key: "enable-command-block",
            displayName: "Enable Command Blocks",
            description: "Allow command blocks to execute commands.",
            category: .administration,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "function-permission-level",
            displayName: "Function Permission Level",
            description: "Permission level required to run functions.",
            category: .administration,
            inputType: .integer(min: 1, max: 4, unit: nil),
            defaultValue: "2",
            isAdvanced: true
        ),

        // Performance
        PropertyMetadata(
            key: "max-tick-time",
            displayName: "Max Tick Time",
            description: "Maximum milliseconds per tick before watchdog kills server (-1 to disable).",
            category: .performance,
            inputType: .integer(min: -1, max: 600000, unit: "ms"),
            defaultValue: "60000",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "sync-chunk-writes",
            displayName: "Sync Chunk Writes",
            description: "Write chunks synchronously (safer but slower).",
            category: .performance,
            inputType: .boolean,
            defaultValue: "true",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "entity-broadcast-range-percentage",
            displayName: "Entity Broadcast Range",
            description: "Percentage of view distance for entity visibility.",
            category: .performance,
            inputType: .integer(min: 10, max: 1000, unit: "%"),
            defaultValue: "100",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "enable-jmx-monitoring",
            displayName: "JMX Monitoring",
            description: "Enable JMX monitoring for performance metrics.",
            category: .performance,
            inputType: .boolean,
            defaultValue: "false",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "debug",
            displayName: "Debug Mode",
            description: "Enable debug logging.",
            category: .performance,
            inputType: .boolean,
            defaultValue: "false",
            isAdvanced: true
        ),

        // Resource Pack
        PropertyMetadata(
            key: "resource-pack",
            displayName: "Resource Pack URL",
            description: "URL to download the server resource pack.",
            category: .resourcePack,
            inputType: .text,
            defaultValue: ""
        ),
        PropertyMetadata(
            key: "resource-pack-sha1",
            displayName: "Resource Pack SHA-1",
            description: "SHA-1 hash of the resource pack for verification.",
            category: .resourcePack,
            inputType: .text,
            defaultValue: ""
        ),
        PropertyMetadata(
            key: "require-resource-pack",
            displayName: "Require Resource Pack",
            description: "Kick players who decline the resource pack.",
            category: .resourcePack,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "resource-pack-prompt",
            displayName: "Resource Pack Prompt",
            description: "Custom message shown when asking players to download the resource pack.",
            category: .resourcePack,
            inputType: .multilineText,
            defaultValue: ""
        ),

        // Other common properties
        PropertyMetadata(
            key: "bug-report-link",
            displayName: "Bug Report Link",
            description: "Custom bug report URL shown to players.",
            category: .other,
            inputType: .text,
            defaultValue: ""
        ),
        PropertyMetadata(
            key: "hide-online-players",
            displayName: "Hide Online Players",
            description: "Hide the player list from the server status.",
            category: .other,
            inputType: .boolean,
            defaultValue: "false"
        ),
        PropertyMetadata(
            key: "player-idle-timeout",
            displayName: "Idle Timeout",
            description: "Kick players after this many minutes of inactivity (0 to disable).",
            category: .other,
            inputType: .integer(min: 0, max: 1440, unit: "minutes"),
            defaultValue: "0"
        ),
        PropertyMetadata(
            key: "max-chained-neighbor-updates",
            displayName: "Max Chained Updates",
            description: "Limit for chained neighbor block updates.",
            category: .other,
            inputType: .integer(min: -1, max: 10000000, unit: nil),
            defaultValue: "1000000",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "log-ips",
            displayName: "Log Player IPs",
            description: "Log player IP addresses in the server log.",
            category: .other,
            inputType: .boolean,
            defaultValue: "true"
        ),
        PropertyMetadata(
            key: "text-filtering-config",
            displayName: "Text Filtering Config",
            description: "Path to text filtering configuration file.",
            category: .other,
            inputType: .text,
            defaultValue: "",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "initial-enabled-packs",
            displayName: "Initial Enabled Packs",
            description: "Data packs to enable by default.",
            category: .other,
            inputType: .text,
            defaultValue: "vanilla",
            isAdvanced: true
        ),
        PropertyMetadata(
            key: "initial-disabled-packs",
            displayName: "Initial Disabled Packs",
            description: "Data packs to disable by default.",
            category: .other,
            inputType: .text,
            defaultValue: "",
            isAdvanced: true
        ),
    ]

    static func metadata(for key: String) -> PropertyMetadata? {
        properties[key]
    }

    static func displayName(for key: String) -> String {
        if let meta = properties[key] {
            return meta.displayName
        }
        // Convert kebab-case to Title Case
        return key.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func category(for key: String) -> PropertyCategory {
        properties[key]?.category ?? .other
    }
}

// MARK: - Server Property Model

struct ServerProperty: Identifiable, Equatable {
    let id = UUID()
    var key: String
    var value: String
    var originalValue: String
    var comment: String?

    var isModified: Bool {
        value != originalValue
    }

    var metadata: PropertyMetadata? {
        PropertyRegistry.metadata(for: key)
    }

    var displayName: String {
        PropertyRegistry.displayName(for: key)
    }

    var category: PropertyCategory {
        PropertyRegistry.category(for: key)
    }

    var description: String? {
        metadata?.description
    }

    var inputType: PropertyInputType {
        metadata?.inputType ?? (isBooleanProperty ? .boolean : .text)
    }

    var isBooleanProperty: Bool {
        ["true", "false"].contains(value.lowercased())
    }

    var boolValue: Bool {
        get { value.lowercased() == "true" }
        set { value = newValue ? "true" : "false" }
    }

    var isAdvanced: Bool {
        metadata?.isAdvanced ?? false
    }

    static func == (lhs: ServerProperty, rhs: ServerProperty) -> Bool {
        lhs.key == rhs.key && lhs.value == rhs.value
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
    @State private var errorMessage: String?
    @State private var expandedCategories: Set<PropertyCategory> = Set(PropertyCategory.allCases)
    @State private var showAdvanced = false
    @State private var selectedCategory: PropertyCategory?

    var hasChanges: Bool {
        properties.contains { $0.isModified }
    }

    var modifiedCount: Int {
        properties.filter { $0.isModified }.count
    }

    var groupedProperties: [(PropertyCategory, [ServerProperty])] {
        let filtered = filteredProperties
        var groups: [PropertyCategory: [ServerProperty]] = [:]

        for property in filtered {
            groups[property.category, default: []].append(property)
        }

        return PropertyCategory.allCases
            .filter { groups[$0] != nil }
            .map { ($0, groups[$0]!) }
    }

    var filteredProperties: [ServerProperty] {
        var result = properties

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.value.localizedCaseInsensitiveContains(searchText) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Filter by selected category
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        // Filter advanced properties
        if !showAdvanced {
            result = result.filter { !$0.isAdvanced }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                // Main content
                HStack(spacing: 16) {
                    // Category sidebar (for larger screens)
                    if properties.count > 20 {
                        categorySidebar
                            .frame(width: 180)
                            .padding(.leading, 20)
                    }

                    // Properties list
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Grouped properties
                            ForEach(groupedProperties, id: \.0) { category, props in
                                CategoryCard(
                                    category: category,
                                    properties: props,
                                    isExpanded: Binding(
                                        get: { expandedCategories.contains(category) },
                                        set: { if $0 { expandedCategories.insert(category) } else { expandedCategories.remove(category) } }
                                    ),
                                    propertyBinding: { prop in binding(for: prop) }
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
        }
        .onAppear {
            Task { await loadProperties() }
        }
    }

    // MARK: - Subviews

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(PremiumColors.textMuted)
                    .font(.system(size: 12))

                TextField("Search properties...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(PremiumColors.textMuted)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .frame(maxWidth: 280)

            // Filter chips
            HStack(spacing: 8) {
                FilterChip(
                    title: "Show Advanced",
                    isSelected: $showAdvanced,
                    color: PremiumColors.violet
                )

                if hasChanges {
                    FilterChip(
                        title: "\(modifiedCount) Modified",
                        isSelected: .constant(true),
                        color: PremiumColors.amber
                    )
                }
            }

            Spacer()

            // Property count
            Text("\(filteredProperties.count) of \(properties.count) properties")
                .font(.system(size: 12))
                .foregroundColor(PremiumColors.textMuted)

            // Reload button
            GlassIconButton(icon: "arrow.clockwise") {
                Task { await loadProperties() }
            }
            .disabled(isLoading)

            // Save button
            if hasChanges {
                GlassButton(title: "Save Changes", icon: "square.and.arrow.down", style: .primary) {
                    Task { await saveProperties() }
                }
                .disabled(isSaving)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CATEGORIES")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(PremiumColors.textMuted)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(PropertyCategory.allCases) { category in
                let count = properties.filter { $0.category == category && (!$0.isAdvanced || showAdvanced) }.count
                if count > 0 {
                    CategorySidebarItem(
                        category: category,
                        count: count,
                        isSelected: selectedCategory == category,
                        onTap: {
                            withAnimation(.spring(response: 0.3)) {
                                if selectedCategory == category {
                                    selectedCategory = nil
                                } else {
                                    selectedCategory = category
                                }
                            }
                        }
                    )
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .padding(.vertical, 20)
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading server.properties...")
                .font(.system(size: 13))
                .foregroundColor(PremiumColors.textMuted)
                .padding(.top, 12)
            Spacer()
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(PremiumColors.amber)

            Text("Failed to Load Properties")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(PremiumColors.textPrimary)

            Text(error)
                .font(.system(size: 13))
                .foregroundColor(PremiumColors.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            GlassButton(title: "Retry", icon: "arrow.clockwise", style: .secondary) {
                Task { await loadProperties() }
            }
            Spacer()
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProperties() async {
        isSaving = true
        defer { isSaving = false }

        let ssh = serverManager.sshService(for: server)
        let propertiesPath = "\(server.serverPath)/server.properties"

        var lines: [String] = []
        for property in properties {
            if let comment = property.comment {
                lines.append(comment)
            }
            lines.append("\(property.key)=\(property.value)")
        }
        let content = lines.joined(separator: "\n")

        let escapedContent = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")

        let command = "printf \"%s\" \"\(escapedContent)\" > '\(propertiesPath)'"

        do {
            _ = try await ssh.execute(command)
            // Update original values after successful save
            for i in properties.indices {
                properties[i].originalValue = properties[i].value
            }
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
                originalValue: value,
                comment: pendingComment
            ))
            pendingComment = nil
        }

        return result
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    @Binding var isSelected: Bool
    let color: Color

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.2)) {
                isSelected.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : PremiumColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule()
                    .fill(isSelected ? color : Color.white.opacity(0.05))
            }
            .overlay {
                Capsule()
                    .stroke(isSelected ? color.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Sidebar Item

struct CategorySidebarItem: View {
    let category: PropertyCategory
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: category.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? category.accentColor : PremiumColors.textMuted)
                    .frame(width: 20)

                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? PremiumColors.textPrimary : PremiumColors.textSecondary)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PremiumColors.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? category.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(category.accentColor.opacity(0.3), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: PropertyCategory
    let properties: [ServerProperty]
    @Binding var isExpanded: Bool
    let propertyBinding: (ServerProperty) -> Binding<ServerProperty>

    @State private var isHovered = false

    var modifiedCount: Int {
        properties.filter { $0.isModified }.count
    }

    // Separate MOTD from other properties and put it at the end
    var sortedProperties: [ServerProperty] {
        let motd = properties.filter { $0.key == "motd" }
        let others = properties.filter { $0.key != "motd" }
        return others + motd
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(category.accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: category.icon)
                            .font(.system(size: 14))
                            .foregroundColor(category.accentColor)
                    }

                    // Title and count
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PremiumColors.textPrimary)

                        Text("\(properties.count) properties")
                            .font(.system(size: 11))
                            .foregroundColor(PremiumColors.textMuted)
                    }

                    Spacer()

                    // Modified badge
                    if modifiedCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(PremiumColors.amber)
                                .frame(width: 6, height: 6)
                            Text("\(modifiedCount) modified")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(PremiumColors.amber)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(PremiumColors.amber.opacity(0.15))
                        }
                    }

                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PremiumColors.textMuted)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // Properties
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.1))

                    ForEach(sortedProperties) { property in
                        if property.key == "motd" {
                            // Special MOTD editor
                            MotdPropertyRow(property: propertyBinding(property))
                        } else {
                            SmartPropertyRow(property: propertyBinding(property))
                        }

                        if property.id != sortedProperties.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.05))
                                .padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .background {
            PremiumCardBackground(accentColor: category.accentColor, isHovered: isHovered)
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - MOTD Property Row (Special editor with preview)

struct MotdPropertyRow: View {
    @Binding var property: ServerProperty

    @State private var showColorPicker = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 28, height: 28)

                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                }

                // Title
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Message of the Day")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(PremiumColors.textPrimary)

                        if property.isModified {
                            Circle()
                                .fill(PremiumColors.amber)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Text("Displayed in the Minecraft server list")
                        .font(.system(size: 11))
                        .foregroundColor(PremiumColors.textMuted)
                }

                Spacer()
            }

            // Preview
            VStack(alignment: .leading, spacing: 6) {
                Text("PREVIEW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(PremiumColors.textMuted)

                HStack(spacing: 10) {
                    // Server icon placeholder
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "cube.fill")
                                .font(.system(size: 14))
                                .foregroundColor(PremiumColors.textMuted.opacity(0.5))
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Server Name")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(PremiumColors.textPrimary)

                        MinecraftFormattedText(text: property.value.isEmpty ? "A Minecraft Server" : property.value)
                    }

                    Spacer()

                    // Player count mockup
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(PremiumColors.emerald)
                                .frame(width: 6, height: 6)
                            Text("0/20")
                                .font(.system(size: 10))
                                .foregroundColor(PremiumColors.textMuted)
                        }
                    }
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                }
            }

            // Editor
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EDIT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(PremiumColors.textMuted)

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            showColorPicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showColorPicker ? "paintpalette.fill" : "paintpalette")
                                .font(.system(size: 10))
                            Text("Colors")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(showColorPicker ? .purple : PremiumColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(showColorPicker ? Color.purple.opacity(0.15) : Color.white.opacity(0.05))
                        }
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $property.value)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 50, maxHeight: 80)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.03))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            }
                    }

                // Color picker
                if showColorPicker {
                    MotdColorPicker(onSelect: { code in
                        property.value += code
                    })
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // Tips
                HStack(spacing: 12) {
                    Label("§c for colors", systemImage: "paintbrush.fill")
                    Label("\\n for new line", systemImage: "arrow.turn.down.left")
                }
                .font(.system(size: 9))
                .foregroundColor(PremiumColors.textMuted.opacity(0.7))
            }
        }
        .padding(16)
        .background {
            Rectangle()
                .fill(isHovered ? Color.white.opacity(0.02) : Color.clear)
        }
        .onHover { isHovered = $0 }
    }
}

// MARK: - MOTD Color Picker (Compact)

struct MotdColorPicker: View {
    let onSelect: (String) -> Void

    let colors: [(code: String, color: Color)] = [
        ("§0", Color(hex: "000000")),
        ("§1", Color(hex: "0000AA")),
        ("§2", Color(hex: "00AA00")),
        ("§3", Color(hex: "00AAAA")),
        ("§4", Color(hex: "AA0000")),
        ("§5", Color(hex: "AA00AA")),
        ("§6", Color(hex: "FFAA00")),
        ("§7", Color(hex: "AAAAAA")),
        ("§8", Color(hex: "555555")),
        ("§9", Color(hex: "5555FF")),
        ("§a", Color(hex: "55FF55")),
        ("§b", Color(hex: "55FFFF")),
        ("§c", Color(hex: "FF5555")),
        ("§d", Color(hex: "FF55FF")),
        ("§e", Color(hex: "FFFF55")),
        ("§f", Color(hex: "FFFFFF")),
    ]

    let styles: [(code: String, icon: String)] = [
        ("§l", "bold"),
        ("§o", "italic"),
        ("§n", "underline"),
        ("§m", "strikethrough"),
        ("§r", "arrow.counterclockwise"),
    ]

    var body: some View {
        HStack(spacing: 16) {
            // Colors
            HStack(spacing: 4) {
                ForEach(colors, id: \.code) { item in
                    Button {
                        onSelect(item.code)
                    } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(item.color)
                            .frame(width: 18, height: 18)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .frame(height: 18)

            // Styles
            HStack(spacing: 4) {
                ForEach(styles, id: \.code) { item in
                    Button {
                        onSelect(item.code)
                    } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 10))
                            .foregroundColor(PremiumColors.textSecondary)
                            .frame(width: 22, height: 18)
                            .background {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.05))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.2))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                }
        }
    }
}

// MARK: - Smart Property Row

struct SmartPropertyRow: View {
    @Binding var property: ServerProperty

    @State private var isEditing = false
    @State private var editValue: String = ""
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Property info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(property.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(PremiumColors.textPrimary)

                    if property.isModified {
                        Circle()
                            .fill(PremiumColors.amber)
                            .frame(width: 6, height: 6)
                    }

                    if property.isAdvanced {
                        Text("ADVANCED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(PremiumColors.violet)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(PremiumColors.violet.opacity(0.2))
                            }
                    }
                }

                if let description = property.description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(PremiumColors.textMuted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Value editor
            propertyEditor
        }
        .padding(16)
        .background {
            Rectangle()
                .fill(isHovered ? Color.white.opacity(0.02) : Color.clear)
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var propertyEditor: some View {
        switch property.inputType {
        case .boolean:
            BooleanToggle(value: Binding(
                get: { property.boolValue },
                set: { property.value = $0 ? "true" : "false" }
            ))

        case .enumeration(let options):
            EnumPicker(value: $property.value, options: options)

        case .integer(let min, let max, let unit):
            IntegerInput(
                value: $property.value,
                min: min,
                max: max,
                unit: unit
            )

        case .port:
            PortInput(value: $property.value)

        case .password:
            PasswordInput(value: $property.value)

        case .multilineText:
            // Handled by MOTD section for motd, simple text for others
            TextInput(value: $property.value, isEditing: $isEditing, editValue: $editValue)

        case .text:
            TextInput(value: $property.value, isEditing: $isEditing, editValue: $editValue)
        }
    }
}

// MARK: - Input Components

struct BooleanToggle: View {
    @Binding var value: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(value ? "Enabled" : "Disabled")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(value ? PremiumColors.emerald : PremiumColors.textMuted)

            Toggle("", isOn: $value)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(PremiumColors.emerald)
        }
    }
}

struct EnumPicker: View {
    @Binding var value: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    value = option
                } label: {
                    HStack {
                        Text(formatOption(option))
                        if value == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(formatOption(value))
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
            }
            .foregroundColor(PremiumColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        .menuStyle(.borderlessButton)
    }

    private func formatOption(_ option: String) -> String {
        // Remove minecraft: prefix and capitalize
        let cleaned = option.replacingOccurrences(of: "minecraft:", with: "")
        return cleaned.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

struct IntegerInput: View {
    @Binding var value: String
    let min: Int?
    let max: Int?
    let unit: String?

    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var intValue: Int {
        Int(value) ?? 0
    }

    var body: some View {
        HStack(spacing: 8) {
            // Decrement button
            Button {
                if let minVal = min, intValue <= minVal { return }
                value = String(intValue - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PremiumColors.textMuted)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.05))
                    }
            }
            .buttonStyle(.plain)

            // Value field
            HStack(spacing: 4) {
                TextField("", text: $value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(PremiumColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .focused($isFocused)

                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundColor(PremiumColors.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isFocused ? PremiumColors.indigo.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                    }
            }

            // Increment button
            Button {
                if let maxVal = max, intValue >= maxVal { return }
                value = String(intValue + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PremiumColors.textMuted)
                    .frame(width: 24, height: 24)
                    .background {
                        Circle()
                            .fill(Color.white.opacity(0.05))
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

struct PortInput: View {
    @Binding var value: String

    @FocusState private var isFocused: Bool

    var isValid: Bool {
        guard let port = Int(value) else { return false }
        return port >= 1 && port <= 65535
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(isValid ? PremiumColors.textPrimary : PremiumColors.rose)
                .frame(width: 70)
                .focused($isFocused)

            if !isValid && !value.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PremiumColors.rose)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isFocused ? PremiumColors.indigo.opacity(0.5) :
                                (!isValid && !value.isEmpty ? PremiumColors.rose.opacity(0.5) : Color.white.opacity(0.1)),
                            lineWidth: 1
                        )
                }
        }
    }
}

struct PasswordInput: View {
    @Binding var value: String

    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField("", text: $value)
                } else {
                    SecureField("", text: $value)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(PremiumColors.textPrimary)
            .frame(minWidth: 120)
            .focused($isFocused)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PremiumColors.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isFocused ? PremiumColors.indigo.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
}

struct TextInput: View {
    @Binding var value: String
    @Binding var isEditing: Bool
    @Binding var editValue: String

    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField("", text: $editValue, onCommit: {
                value = editValue
                isEditing = false
            })
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(PremiumColors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 180)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(PremiumColors.indigo.opacity(0.5), lineWidth: 1)
                    }
            }
            .focused($isFocused)
            .onAppear {
                editValue = value
                isFocused = true
            }
        } else {
            Button {
                editValue = value
                isEditing = true
            } label: {
                Text(value.isEmpty ? "(empty)" : value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(value.isEmpty ? PremiumColors.textSubtle : PremiumColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 180, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            }
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - MOTD Section with Preview

struct MotdSection: View {
    @Binding var property: ServerProperty
    @Binding var isExpanded: Bool

    @State private var showColorPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 32, height: 32)

                    Image(systemName: "text.bubble.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 14))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Message of the Day")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(PremiumColors.textPrimary)

                    Text("Displayed in the server list")
                        .font(.system(size: 11))
                        .foregroundColor(PremiumColors.textMuted)
                }

                Spacer()

                if property.isModified {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(PremiumColors.amber)
                            .frame(width: 6, height: 6)
                        Text("Modified")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PremiumColors.amber)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(PremiumColors.amber.opacity(0.15))
                    }
                }
            }

            // Preview - Mimics Minecraft server list appearance
            VStack(alignment: .leading, spacing: 8) {
                Text("PREVIEW")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(PremiumColors.textMuted)

                HStack(spacing: 12) {
                    // Server icon placeholder
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "cube.fill")
                                .foregroundColor(PremiumColors.textMuted)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(PremiumColors.textPrimary)

                        MinecraftFormattedText(text: property.value)
                    }

                    Spacer()

                    // Player count mockup
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(PremiumColors.emerald)
                                .frame(width: 8, height: 8)
                            Text("0/20")
                                .font(.system(size: 11))
                                .foregroundColor(PremiumColors.textMuted)
                        }
                        Text("1ms")
                            .font(.system(size: 10))
                            .foregroundColor(PremiumColors.textMuted)
                    }
                }
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                }
            }

            // Editor
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EDIT MOTD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(PremiumColors.textMuted)

                    Spacer()

                    Button {
                        showColorPicker.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 10))
                            Text("Colors")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(PremiumColors.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                        }
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $property.value)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 60, maxHeight: 100)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            }
                    }

                // Color picker panel
                if showColorPicker {
                    MinecraftColorPicker(onSelect: { code in
                        property.value += code
                    })
                }

                // Tips
                HStack(spacing: 16) {
                    Label("Use §c for colors", systemImage: "paintbrush.fill")
                    Label("Use \\n for new line", systemImage: "arrow.turn.down.left")
                }
                .font(.system(size: 10))
                .foregroundColor(PremiumColors.textMuted)
            }
        }
        .padding(20)
        .background {
            PremiumCardBackground(accentColor: .purple, isHovered: false)
        }
    }
}

// MARK: - Minecraft Color Picker

struct MinecraftColorPicker: View {
    let onSelect: (String) -> Void

    let colors: [(code: String, name: String, color: Color)] = [
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
        ("§d", "Pink", Color(hex: "FF55FF")),
        ("§e", "Yellow", Color(hex: "FFFF55")),
        ("§f", "White", Color(hex: "FFFFFF")),
    ]

    let styles: [(code: String, name: String, icon: String)] = [
        ("§l", "Bold", "bold"),
        ("§o", "Italic", "italic"),
        ("§n", "Underline", "underline"),
        ("§m", "Strike", "strikethrough"),
        ("§r", "Reset", "arrow.counterclockwise"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Colors
            Text("Colors")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(PremiumColors.textMuted)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 6), count: 8), spacing: 6) {
                ForEach(colors, id: \.code) { item in
                    Button {
                        onSelect(item.code)
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }

            // Styles
            Text("Styles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(PremiumColors.textMuted)

            HStack(spacing: 8) {
                ForEach(styles, id: \.code) { item in
                    Button {
                        onSelect(item.code)
                    } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 12))
                            .foregroundColor(PremiumColors.textSecondary)
                            .frame(width: 32, height: 28)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.05))
                            }
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }
}

// MARK: - Minecraft Formatted Text (reused from original)

struct MinecraftFormattedText: View {
    let text: String

    var body: some View {
        Text(parseMinecraftFormatting(text))
            .font(.system(size: 13, design: .monospaced))
    }

    private func parseMinecraftFormatting(_ input: String) -> AttributedString {
        var result = AttributedString()

        let processedInput = input.replacingOccurrences(of: "\\n", with: "\n")

        let colors: [Character: Color] = [
            "0": Color(hex: "000000"),
            "1": Color(hex: "0000AA"),
            "2": Color(hex: "00AA00"),
            "3": Color(hex: "00AAAA"),
            "4": Color(hex: "AA0000"),
            "5": Color(hex: "AA00AA"),
            "6": Color(hex: "FFAA00"),
            "7": Color(hex: "AAAAAA"),
            "8": Color(hex: "555555"),
            "9": Color(hex: "5555FF"),
            "a": Color(hex: "55FF55"),
            "b": Color(hex: "55FFFF"),
            "c": Color(hex: "FF5555"),
            "d": Color(hex: "FF55FF"),
            "e": Color(hex: "FFFF55"),
            "f": Color(hex: "FFFFFF")
        ]

        var currentColor: Color = .white
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrikethrough = false

        var currentText = ""
        var i = processedInput.startIndex

        while i < processedInput.endIndex {
            let char = processedInput[i]

            if (char == "§" || char == "&") && processedInput.index(after: i) < processedInput.endIndex {
                if !currentText.isEmpty {
                    var attr = AttributedString(currentText)
                    attr.foregroundColor = currentColor
                    if isBold { attr.font = .system(size: 13, weight: .bold, design: .monospaced) }
                    if isItalic { attr.font = (attr.font ?? .system(size: 13, design: .monospaced)).italic() }
                    if isUnderline { attr.underlineStyle = .single }
                    if isStrikethrough { attr.strikethroughStyle = .single }
                    result.append(attr)
                    currentText = ""
                }

                let codeIndex = processedInput.index(after: i)
                let code = processedInput[codeIndex].lowercased().first!

                if let color = colors[code] {
                    currentColor = color
                    isBold = false
                    isItalic = false
                    isUnderline = false
                    isStrikethrough = false
                } else {
                    switch code {
                    case "l": isBold = true
                    case "o": isItalic = true
                    case "n": isUnderline = true
                    case "m": isStrikethrough = true
                    case "k": break
                    case "r":
                        currentColor = .white
                        isBold = false
                        isItalic = false
                        isUnderline = false
                        isStrikethrough = false
                    default: break
                    }
                }

                i = processedInput.index(after: codeIndex)
            } else {
                currentText.append(char)
                i = processedInput.index(after: i)
            }
        }

        if !currentText.isEmpty {
            var attr = AttributedString(currentText)
            attr.foregroundColor = currentColor
            if isBold { attr.font = .system(size: 13, weight: .bold, design: .monospaced) }
            if isItalic { attr.font = (attr.font ?? .system(size: 13, design: .monospaced)).italic() }
            if isUnderline { attr.underlineStyle = .single }
            if isStrikethrough { attr.strikethroughStyle = .single }
            result.append(attr)
        }

        return result
    }
}
