//
//  DashboardView.swift
//  MCPanel
//
//  Real-time server performance dashboard with TPS, memory, players, and charts
//

import SwiftUI
import Charts
import Combine

// MARK: - Premium Design System

/// Premium color palette with refined, elegant tones
enum PremiumColors {
    // Primary accent colors
    static let emerald = Color(hex: "10B981")      // Success/Good - richer green
    static let amber = Color(hex: "F59E0B")        // Warning
    static let rose = Color(hex: "F43F5E")         // Critical/Error
    static let indigo = Color(hex: "6366F1")       // Primary accent
    static let violet = Color(hex: "8B5CF6")       // Secondary accent
    static let teal = Color(hex: "14B8A6")         // Network/Info
    static let sky = Color(hex: "0EA5E9")          // Links/Actions
    static let slate = Color(hex: "64748B")        // Muted text

    // Card backgrounds with subtle tints
    static let cardBg = Color.white.opacity(0.03)
    static let cardBgHover = Color.white.opacity(0.05)
    static let cardBorder = Color.white.opacity(0.08)
    static let cardBorderHover = Color.white.opacity(0.15)

    // Text hierarchy
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textMuted = Color.white.opacity(0.45)
    static let textSubtle = Color.white.opacity(0.3)

    // Semantic colors for metrics
    static func tpsColor(_ tps: Double?) -> Color {
        guard let tps = tps else { return slate }
        if tps >= 19.5 { return emerald }
        if tps >= 18 { return Color(hex: "84CC16") }  // Lime for "good"
        if tps >= 15 { return amber }
        return rose
    }

    static func msptColor(_ mspt: Double?) -> Color {
        guard let mspt = mspt else { return slate }
        if mspt < 35 { return emerald }
        if mspt < 45 { return amber }
        return rose
    }

    static func memoryColor(_ percent: Double) -> Color {
        if percent < 0.65 { return emerald }
        if percent < 0.80 { return amber }
        return rose
    }

    static func cpuColor(_ percent: Double) -> Color {
        if percent < 50 { return indigo }
        if percent < 75 { return amber }
        return rose
    }

    static func diskColor(_ percent: Double) -> Color {
        if percent < 70 { return emerald }
        if percent < 85 { return amber }
        return rose
    }
}

/// Premium typography styles
enum PremiumTypography {
    static let heroValue = Font.system(size: 48, weight: .bold, design: .rounded)
    static let largeValue = Font.system(size: 36, weight: .bold, design: .rounded)
    static let mediumValue = Font.system(size: 28, weight: .bold, design: .rounded)
    static let smallValue = Font.system(size: 20, weight: .semibold, design: .rounded)

    static let sectionHeader = Font.system(size: 10, weight: .semibold, design: .default)
    static let cardHeader = Font.system(size: 11, weight: .medium, design: .default)
    static let label = Font.system(size: 10, weight: .medium, design: .default)
    static let caption = Font.system(size: 9, weight: .regular, design: .default)

    static let monoLarge = Font.system(size: 14, weight: .bold, design: .monospaced)
    static let monoMedium = Font.system(size: 12, weight: .semibold, design: .monospaced)
    static let monoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)
}

/// Premium spacing and sizing constants
enum PremiumMetrics {
    static let cardPadding: CGFloat = 20
    static let cardCornerRadius: CGFloat = 16
    static let cardSpacing: CGFloat = 16
    static let innerSpacing: CGFloat = 12
    static let tightSpacing: CGFloat = 8
    static let microSpacing: CGFloat = 4

    static let primaryCardMinHeight: CGFloat = 180
    static let secondaryCardMinHeight: CGFloat = 160

    static let sparklineHeight: CGFloat = 40
    static let miniSparklineHeight: CGFloat = 28
    static let progressBarHeight: CGFloat = 6

    static let iconSizeSmall: CGFloat = 12
    static let iconSizeMedium: CGFloat = 16
    static let iconSizeLarge: CGFloat = 20
}

// MARK: - Premium Card Background

/// Reusable premium glass card background with inner glow
struct PremiumCardBackground: View {
    let accentColor: Color
    let isHovered: Bool
    var cornerRadius: CGFloat = PremiumMetrics.cardCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                // Inner glow at top
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.15 : 0.08),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                // Accent color glow on hover
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(isHovered ? 0.25 : 0), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Equal Height HStack

/// A horizontal stack that ensures all children have equal heights
/// Uses SwiftUI preferences to measure the tallest child and apply that height to all
struct EqualHeightHStack<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    @State private var maxHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            content
        }
        .onPreferenceChange(CardHeightPreference.self) { heights in
            if let max = heights.max(), max > 0 {
                maxHeight = max
            }
        }
        .environment(\.cardTargetHeight, maxHeight > 0 ? maxHeight : nil)
    }

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
}

/// Preference key for collecting card heights
struct CardHeightPreference: PreferenceKey {
    static var defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}

/// Environment key for target card height
struct CardTargetHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var cardTargetHeight: CGFloat? {
        get { self[CardTargetHeightKey.self] }
        set { self[CardTargetHeightKey.self] = newValue }
    }
}

/// View modifier to report height and apply target height
struct EqualHeightModifier: ViewModifier {
    @Environment(\.cardTargetHeight) private var targetHeight

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CardHeightPreference.self,
                        value: [geo.size.height]
                    )
                }
            }
            .frame(height: targetHeight, alignment: .top)
    }
}

extension View {
    func equalHeight() -> some View {
        modifier(EqualHeightModifier())
    }
}

// MARK: - Animated Number View

/// Animates number changes smoothly
struct AnimatedNumber: View {
    let value: Double
    let format: String
    let font: Font
    let color: Color

    @State private var displayValue: Double = 0

    var body: some View {
        Text(String(format: format, displayValue))
            .font(font)
            .foregroundColor(color)
            .contentTransition(.numericText(value: displayValue))
            .onChange(of: value) { _, newValue in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    displayValue = newValue
                }
            }
            .onAppear {
                displayValue = value
            }
    }
}

// MARK: - Bridge Observer

/// Helper class to observe MCPanelBridgeService changes and trigger SwiftUI updates
@MainActor
class BridgeObserver: ObservableObject {
    @Published var bridgeDetected: Bool = false
    @Published var serverStatus: StatusUpdatePayload?
    @Published var playerList: PlayersUpdatePayload?

    private var cancellables = Set<AnyCancellable>()

    var bridge: MCPanelBridgeService? {
        didSet {
            cancellables.removeAll()
            guard let bridge = bridge else { return }

            // Subscribe to bridge changes
            bridge.$bridgeDetected
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    self?.bridgeDetected = value
                }
                .store(in: &cancellables)

            bridge.$serverStatus
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    self?.serverStatus = value
                }
                .store(in: &cancellables)

            bridge.$playerList
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    self?.playerList = value
                }
                .store(in: &cancellables)

            // Initialize with current values
            bridgeDetected = bridge.bridgeDetected
            serverStatus = bridge.serverStatus
            playerList = bridge.playerList
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var serverManager: ServerManager
    let server: Server

    /// Observe the bridge service to react to changes in bridgeDetected, serverStatus, etc.
    @StateObject private var bridgeObserver = BridgeObserver()

    var body: some View {
        // Get the bridge service
        let bridge = serverManager.bridgeServices[server.id]

        // Check if bridge has data - use observer OR direct bridge check for immediate display
        let hasBridgeData = bridgeObserver.bridgeDetected || (bridge?.bridgeDetected == true)

        ScrollView {
            VStack(spacing: 20) {
                // Show full dashboard if bridge has data
                if hasBridgeData, let _ = bridge {
                    // Bridge is available - show full dashboard
                    metricsGrid

                    performanceChart

                    playerIndicator
                } else if serverManager.ptyConnected[server.id] == true {
                    // PTY connected but bridge not detected yet - show waiting state
                    waitingForBridge
                } else {
                    // No PTY connection yet - show connecting state or fallback
                    if server.consoleMode != .logTail {
                        connectingState
                    } else {
                        // Log tail mode doesn't support bridge
                        noBridgeFallback
                    }
                }
            }
            .padding(24)
        }
        .background(Color(hex: "161618"))
        .onAppear {
            // Connect to bridge service for observation immediately
            if let bridge = serverManager.bridgeServices[server.id] {
                bridgeObserver.bridge = bridge
            }
            // Ensure PTY is connected so we can receive bridge events
            // The bridge detection happens via OSC messages in the PTY stream
            Task {
                await serverManager.acquirePTY(for: server, consumer: .monitor)
            }
            // Request high-frequency updates when monitor is visible
            serverManager.setDashboardActive(true, for: server.id)
        }
        .onDisappear {
            // Revert to low-frequency updates
            serverManager.setDashboardActive(false, for: server.id)
            serverManager.releasePTY(for: server, consumer: .monitor)
        }
        .onReceive(serverManager.$bridgeServices) { services in
            // Update our observer when bridge service changes
            if let bridge = services[server.id] {
                bridgeObserver.bridge = bridge
            }
        }
    }

    // MARK: - Server Header

    private var serverHeader: some View {
        let bridge = serverManager.bridgeServices[server.id]
        let status = bridge?.serverStatus

        return HStack(spacing: 16) {
            // Server icon
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "22C55E").opacity(0.3), Color(hex: "22C55E").opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)

                Image(systemName: "server.rack")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color(hex: "22C55E"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    GlassStatusBadge(status: server.status)

                    // Uptime badge (moved from separate card)
                    if let status = status {
                        UptimeBadge(seconds: status.uptimeSeconds)
                    }

                    // Player count badge
                    if let status = status {
                        PlayerCountBadge(count: status.playerCount, max: status.maxPlayers)
                    }

                    // System info badge (CPU model)
                    SystemInfoBadge(systemInfo: bridge?.systemInfo)
                }
            }

            Spacer()

            // Quick actions
            HStack(spacing: 8) {
                if server.status == .online {
                    GlassIconButton(icon: "arrow.clockwise") {
                        Task { await serverManager.restartServer(server) }
                    }

                    GlassIconButton(icon: "stop.fill", tint: .red) {
                        Task { await serverManager.stopServer(server) }
                    }
                } else if server.status == .offline {
                    GlassIconButton(icon: "play.fill", tint: .green) {
                        Task { await serverManager.startServer(server) }
                    }
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    // MARK: - Metrics Grid (Premium Layout)

    private var metricsGrid: some View {
        let bridge = serverManager.bridgeServices[server.id]
        let status = bridge?.serverStatus
        let history = bridge?.performanceHistory
        let systemInfo = bridge?.systemInfo
        let cpuHistory: [PerformanceHistory.DataPoint] = {
            guard let status, let history else { return [] }
            if status.cpuUsagePercent != nil {
                return history.cpuHistory
            }
            if status.systemCpuPercent != nil {
                return history.systemCpuHistory
            }
            return []
        }()

        return VStack(spacing: PremiumMetrics.cardSpacing) {
            // Primary row: Tick Performance + Resource Monitor
            EqualHeightHStack(spacing: PremiumMetrics.cardSpacing) {
                PremiumTickPerformanceCard(
                    tps: status?.tps,
                    mspt: status?.mspt,
                    tpsHistory: history?.tpsHistory ?? [],
                    msptHistory: history?.msptHistory ?? []
                )

                PremiumResourceMonitorCard(
                    usedMemoryMB: status?.usedMemoryMB ?? 0,
                    maxMemoryMB: status?.maxMemoryMB ?? 1,
                    cpuPercent: status?.cpuUsagePercent,
                    systemCpuPercent: status?.systemCpuPercent,
                    threadCount: status?.threadCount,
                    cpuModel: systemInfo?.cpuModel,
                    cpuCores: systemInfo?.cpuCores,
                    memoryHistory: history?.memoryHistory ?? [],
                    cpuHistory: cpuHistory
                )
            }

            // Secondary row: Disk + Network
            EqualHeightHStack(spacing: PremiumMetrics.cardSpacing) {
                PremiumDiskUsageCard(
                    disks: status?.disks,
                    history: history?.diskHistory ?? []
                )

                PremiumNetworkUsageCard(
                    network: status?.network,
                    rxHistory: history?.networkRxHistory ?? [],
                    txHistory: history?.networkTxHistory ?? []
                )
            }

            // System Info Card (collapsible details about Java, OS, hardware)
            if let systemInfo = systemInfo {
                PremiumSystemInfoCard(systemInfo: systemInfo)
            }
        }
    }

    // MARK: - Player Indicator

    private var playerIndicator: some View {
        let bridge = serverManager.bridgeServices[server.id]
        let status = bridge?.serverStatus
        let history = bridge?.performanceHistory

        return PremiumPlayerIndicator(
            playerCount: status?.playerCount ?? 0,
            maxPlayers: status?.maxPlayers ?? 0,
            players: bridge?.playerList?.players ?? [],
            sparklineData: history?.playerCountHistory.suffix(60).map { $0.value } ?? []
        )
    }

    /// Calculate trend direction from recent data
    private func calculateTrend(_ data: [Double], inverted: Bool = false) -> TrendDirection {
        guard data.count >= 5 else { return .stable }
        let recent = Array(data.suffix(5))
        let older = Array(data.prefix(5))
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        let diff = recentAvg - olderAvg
        let threshold = 0.5

        if abs(diff) < threshold { return .stable }
        let isUp = diff > 0
        if inverted {
            return isUp ? .down : .up  // For MSPT, higher is worse
        }
        return isUp ? .up : .down
    }

    // MARK: - Performance Chart

    private var performanceChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Timeline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)

            if let bridge = serverManager.bridgeServices[server.id],
               !bridge.performanceHistory.tpsHistory.isEmpty {
                PerformanceChartView(history: bridge.performanceHistory)
                    .frame(height: 220)
            } else {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Collecting data...")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                }
                .frame(height: 220)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    // MARK: - Player Section

    private var playerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Online Players")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                if let bridge = serverManager.bridgeServices[server.id],
                   let players = bridge.playerList {
                    Text("\(players.count)/\(players.max)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            if let bridge = serverManager.bridgeServices[server.id],
               let players = bridge.playerList,
               !players.players.isEmpty {
                PlayerGridView(players: players.players)
            } else {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No players online")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    // MARK: - Bridge Info

    private func bridgeInfo(_ bridge: MCPanelBridgeService) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(Color(hex: "22C55E"))

            VStack(alignment: .leading, spacing: 2) {
                Text("MCPanel Bridge Connected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                HStack(spacing: 8) {
                    if let version = bridge.bridgeVersion {
                        Text("v\(version)")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if let platform = bridge.platform {
                        Text(platform)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    if !bridge.features.isEmpty {
                        Text(bridge.features.joined(separator: ", "))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "22C55E").opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "22C55E").opacity(0.2), lineWidth: 1)
                }
        }
    }

    // MARK: - No Bridge Fallback

    private var noBridgeFallback: some View {
        VStack(spacing: 24) {
            // Warning banner
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "EAB308"))
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 4) {
                    Text("MCPanel Bridge Not Detected")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Install the MCPanel Bridge plugin to enable real-time performance monitoring, player tracking, and command completions.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "EAB308").opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: "EAB308").opacity(0.2), lineWidth: 1)
                    }
            }

            // Basic info available without bridge
            VStack(alignment: .leading, spacing: 16) {
                Text("Basic Information")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    BasicInfoCard(
                        title: "Server Status",
                        value: server.status.rawValue,
                        icon: "circle.fill",
                        color: Color(hex: server.status.color)
                    )

                    BasicInfoCard(
                        title: "Connection",
                        value: "\(server.host):\(server.sshPort)",
                        icon: "network",
                        color: .blue
                    )

                    BasicInfoCard(
                        title: "Server Path",
                        value: server.serverPath,
                        icon: "folder.fill",
                        color: .orange
                    )

                    BasicInfoCard(
                        title: "Console Mode",
                        value: server.consoleMode.rawValue,
                        icon: "terminal.fill",
                        color: .purple
                    )
                }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
    }

    // MARK: - Connecting State

    private var connectingState: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connecting to Console...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Establishing PTY connection to receive real-time data from MCPanel Bridge.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    }
            }

            // Show basic info while connecting
            basicInfoSection
        }
    }

    // MARK: - Waiting for Bridge

    private var waitingForBridge: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "EAB308")))
                    .scaleEffect(0.8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Waiting for MCPanel Bridge...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Console connected. Waiting for the MCPanel Bridge plugin to broadcast status updates.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "EAB308").opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: "EAB308").opacity(0.2), lineWidth: 1)
                    }
            }

            // Show basic info while waiting
            basicInfoSection

            // Hint about bridge installation
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.white.opacity(0.5))

                Text("If you don't have the MCPanel Bridge plugin installed, performance metrics won't be available.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Basic Info Section (shared)

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))

                Text("Server Details")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                BasicInfoCard(
                    title: "Status",
                    value: server.status.rawValue,
                    icon: "circle.fill",
                    color: Color(hex: server.status.color)
                )

                BasicInfoCard(
                    title: "Connection",
                    value: "\(server.host):\(server.sshPort)",
                    icon: "network",
                    color: Color(hex: "3B82F6")
                )

                BasicInfoCard(
                    title: "Server Path",
                    value: server.serverPath,
                    icon: "folder.fill",
                    color: Color(hex: "F97316")
                )

                BasicInfoCard(
                    title: "Console Mode",
                    value: server.consoleMode.rawValue,
                    icon: "terminal.fill",
                    color: Color(hex: "A855F7")
                )
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    // MARK: - Helpers

    private func formatUptime(_ seconds: Int64) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func tpsColor(_ tps: Double?) -> Color {
        guard let tps = tps else { return .gray }
        if tps >= 18 { return Color(hex: "22C55E") }  // Green
        if tps >= 15 { return Color(hex: "EAB308") }  // Yellow
        return Color(hex: "EF4444")  // Red
    }

    private func msptColor(_ mspt: Double?) -> Color {
        guard let mspt = mspt else { return .gray }
        if mspt < 40 { return Color(hex: "22C55E") }  // Green
        if mspt < 50 { return Color(hex: "EAB308") }  // Yellow
        return Color(hex: "EF4444")  // Red
    }

    private func memoryColor(_ status: StatusUpdatePayload?) -> Color {
        guard let status = status else { return .gray }
        let percentage = Double(status.usedMemoryMB) / Double(status.maxMemoryMB)
        if percentage < 0.7 { return Color(hex: "22C55E") }  // Green
        if percentage < 0.85 { return Color(hex: "EAB308") }  // Yellow
        return Color(hex: "EF4444")  // Red
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var sparklineData: [Double] = []
    var maxValue: Double? = nil
    var progress: Double? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()
            }

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Progress bar or Sparkline
            if let progress = progress {
                // Memory-style progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.8), color],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(progress, 1.0))
                    }
                }
                .frame(height: 6)
            } else if !sparklineData.isEmpty {
                // Sparkline
                SparklineView(data: sparklineData, color: color, maxValue: maxValue)
                    .frame(height: 32)
            } else {
                Spacer()
                    .frame(height: 32)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sparkline View

struct SparklineView: View {
    let data: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { geometry in
            if data.count > 1 {
                let effectiveMax = maxValue ?? (data.max() ?? 1)
                let effectiveMin = 0.0
                let range = effectiveMax - effectiveMin

                Path { path in
                    for (index, value) in data.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(data.count - 1)
                        let normalizedValue = range > 0 ? (value - effectiveMin) / range : 0.5
                        let y = geometry.size.height * (1 - CGFloat(normalizedValue))

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.5), color],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                // Fill area under curve
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height))

                    for (index, value) in data.enumerated() {
                        let x = geometry.size.width * CGFloat(index) / CGFloat(data.count - 1)
                        let normalizedValue = range > 0 ? (value - effectiveMin) / range : 0.5
                        let y = geometry.size.height * (1 - CGFloat(normalizedValue))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

// MARK: - Premium Performance Timeline (CPU Cores + RAM focused)

struct PerformanceChartView: View {
    @ObservedObject var history: PerformanceHistory
    @State private var selectedTimeRange: TimeRange = .fiveMinutes
    @State private var selectedTime: Date?
    @State private var isHovered = false

    enum TimeRange: String, CaseIterable {
        case oneMinute = "1m"
        case fiveMinutes = "5m"
        case fifteenMinutes = "15m"
        case thirtyMinutes = "30m"

        var sampleCount: Int {
            switch self {
            case .oneMinute: return 120
            case .fiveMinutes: return 600
            case .fifteenMinutes: return 1800
            case .thirtyMinutes: return 3600
            }
        }

        var duration: TimeInterval {
            switch self {
            case .oneMinute: return 60
            case .fiveMinutes: return 300
            case .fifteenMinutes: return 900
            case .thirtyMinutes: return 1800
            }
        }
    }

    private struct TimelineSeriesPoint: Identifiable {
        let id = UUID()
        let time: Date
        let value: Double
        let series: String
        let color: Color
        let lineWidth: Double
    }

    private struct SeriesValue: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let color: Color
    }

    // Generate distinct colors for each CPU core
    private func coreColor(_ index: Int, total: Int) -> Color {
        let colors: [Color] = [
            PremiumColors.indigo,
            PremiumColors.violet,
            PremiumColors.sky,
            PremiumColors.teal,
            Color(hex: "EC4899"),  // Pink
            Color(hex: "F97316"),  // Orange
            Color(hex: "84CC16"),  // Lime
            Color(hex: "06B6D4"),  // Cyan
            Color(hex: "8B5CF6"),  // Violet
            Color(hex: "F43F5E"),  // Rose
            Color(hex: "10B981"),  // Emerald
            Color(hex: "F59E0B"),  // Amber
        ]
        return colors[index % colors.count]
    }

    private func trimRange(
        _ data: [PerformanceHistory.DataPoint],
        start: Date,
        maxSamples: Int
    ) -> [PerformanceHistory.DataPoint] {
        let filtered = data.filter { $0.timestamp >= start }
        if filtered.count > maxSamples {
            return Array(filtered.suffix(maxSamples))
        }
        return filtered
    }

    private func baseTimeline(_ fallback: [PerformanceHistory.DataPoint]...) -> [Date] {
        for series in fallback where !series.isEmpty {
            return series.map { $0.timestamp }
        }
        return []
    }

    private func nearestTime(to target: Date, in times: [Date]) -> Date? {
        guard !times.isEmpty else { return nil }
        var low = 0
        var high = times.count - 1
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let idx = low
        if idx == 0 { return times.first }
        let prev = times[idx - 1]
        let next = times[idx]
        return abs(prev.timeIntervalSince(target)) <= abs(next.timeIntervalSince(target)) ? prev : next
    }

    private func nearestValue(in series: [PerformanceHistory.DataPoint], at time: Date) -> Double? {
        guard !series.isEmpty else { return nil }
        var low = 0
        var high = series.count - 1
        while low < high {
            let mid = (low + high) / 2
            if series[mid].timestamp < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let idx = low
        if idx == 0 { return series.first?.value }
        let prev = series[idx - 1]
        let next = series[idx]
        let chosen = abs(prev.timestamp.timeIntervalSince(time)) <= abs(next.timestamp.timeIntervalSince(time)) ? prev : next
        return chosen.value
    }

    private func buildSeriesPoints(
        memoryData: [PerformanceHistory.DataPoint],
        cpuData: [PerformanceHistory.DataPoint],
        systemCpuData: [PerformanceHistory.DataPoint],
        perCoreData: [[PerformanceHistory.DataPoint]],
        extendTo now: Date
    ) -> [TimelineSeriesPoint] {
        var seriesPoints: [TimelineSeriesPoint] = []

        // Helper to project the last point to "now" if needed
        // This creates a smooth extension of the line to the current time
        func projectToNow(
            _ data: [PerformanceHistory.DataPoint],
            series: String,
            color: Color,
            lineWidth: Double
        ) {
            for point in data {
                seriesPoints.append(TimelineSeriesPoint(
                    time: point.timestamp,
                    value: min(max(point.value, 0), 100),
                    series: series,
                    color: color,
                    lineWidth: lineWidth
                ))
            }

            // Project the last value to current time if there's a gap
            if let lastPoint = data.last {
                let gap = now.timeIntervalSince(lastPoint.timestamp)
                // If there's more than 1 second gap, extend the line
                if gap > 1.0 {
                    seriesPoints.append(TimelineSeriesPoint(
                        time: now,
                        value: min(max(lastPoint.value, 0), 100),
                        series: series,
                        color: color,
                        lineWidth: lineWidth
                    ))
                }
            }
        }

        // RAM usage (purple, prominent)
        projectToNow(memoryData, series: "RAM", color: PremiumColors.violet, lineWidth: 2.5)

        // CPU per core if available
        if !perCoreData.isEmpty {
            for (index, coreSeries) in perCoreData.enumerated() {
                let color = coreColor(index, total: perCoreData.count)
                projectToNow(coreSeries, series: "Core \(index)", color: color, lineWidth: 1.5)
            }
        } else if !cpuData.isEmpty {
            // Aggregate CPU if per-core not available
            projectToNow(cpuData, series: "CPU", color: PremiumColors.indigo, lineWidth: 2)
        } else if !systemCpuData.isEmpty {
            projectToNow(systemCpuData, series: "System CPU", color: PremiumColors.indigo.opacity(0.9), lineWidth: 2)
        }

        return seriesPoints
    }

    private func buildSeriesValues(
        at time: Date,
        memoryData: [PerformanceHistory.DataPoint],
        cpuData: [PerformanceHistory.DataPoint],
        systemCpuData: [PerformanceHistory.DataPoint],
        perCoreData: [[PerformanceHistory.DataPoint]]
    ) -> [SeriesValue] {
        var values: [SeriesValue] = []

        if let mem = nearestValue(in: memoryData, at: time) {
            values.append(SeriesValue(label: "RAM", value: String(format: "%.1f%%", mem), color: PremiumColors.violet))
        }

        if !perCoreData.isEmpty {
            let coreValues = perCoreData.enumerated().compactMap { index, series -> SeriesValue? in
                guard let value = nearestValue(in: series, at: time) else { return nil }
                return SeriesValue(label: "Core \(index)", value: String(format: "%.0f%%", value), color: coreColor(index, total: perCoreData.count))
            }
            values.append(contentsOf: coreValues)
        } else if let cpu = nearestValue(in: cpuData, at: time) {
            values.append(SeriesValue(label: "CPU", value: String(format: "%.1f%%", cpu), color: PremiumColors.indigo))
        } else if let cpu = nearestValue(in: systemCpuData, at: time) {
            values.append(SeriesValue(label: "System CPU", value: String(format: "%.1f%%", cpu), color: PremiumColors.indigo.opacity(0.9)))
        }

        return values
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and time range selector
            HStack {
                HStack(spacing: PremiumMetrics.tightSpacing) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: PremiumMetrics.iconSizeSmall, weight: .semibold))
                        .foregroundColor(PremiumColors.indigo)

                    Text("CPU & MEMORY TIMELINE")
                        .font(PremiumTypography.sectionHeader)
                        .foregroundColor(PremiumColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                Spacer()

                // Time range pills
                HStack(spacing: 4) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Button(action: { withAnimation(.spring(response: 0.2)) { selectedTimeRange = range } }) {
                            Text(range.rawValue)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(selectedTimeRange == range ? .white : PremiumColors.textMuted)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background {
                                    if selectedTimeRange == range {
                                        Capsule()
                                            .fill(PremiumColors.indigo.opacity(0.3))
                                            .overlay {
                                                Capsule()
                                                    .stroke(PremiumColors.indigo.opacity(0.5), lineWidth: 1)
                                            }
                                    } else {
                                        Capsule()
                                            .fill(Color.white.opacity(0.05))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, PremiumMetrics.innerSpacing)

            // Chart area
            let sampleCount = selectedTimeRange.sampleCount
            let rangeEnd = Date()
            let rangeStart = rangeEnd.addingTimeInterval(-selectedTimeRange.duration)
            let memoryData = trimRange(history.memoryHistory, start: rangeStart, maxSamples: sampleCount)
            let cpuData = trimRange(history.cpuHistory, start: rangeStart, maxSamples: sampleCount)
            let systemCpuData = trimRange(history.systemCpuHistory, start: rangeStart, maxSamples: sampleCount)
            let perCoreData = history.perCoreCpuHistory.map { trimRange($0, start: rangeStart, maxSamples: sampleCount) }

            let baseTimeline = baseTimeline(memoryData, cpuData, systemCpuData)
            let seriesPoints = buildSeriesPoints(
                memoryData: memoryData,
                cpuData: cpuData,
                systemCpuData: systemCpuData,
                perCoreData: perCoreData,
                extendTo: rangeEnd
            )

            if !seriesPoints.isEmpty {
                Chart {
                    ForEach(seriesPoints) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Value", point.value),
                            series: .value("Metric", point.series)
                        )
                        .foregroundStyle(point.color)
                        .lineStyle(StrokeStyle(lineWidth: point.lineWidth))
                        .interpolationMethod(.catmullRom)
                    }

                    if let selectedTime {
                        RuleMark(x: .value("Time", selectedTime))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXScale(domain: rangeStart...rangeEnd)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisValueLabel {
                            if let percent = value.as(Double.self) {
                                Text("\(Int(percent))%")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(PremiumColors.textSubtle)
                            }
                        }
                        AxisGridLine()
                            .foregroundStyle(Color.white.opacity(0.06))
                    }
                }
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let rawTime: Date = proxy.value(atX: value.location.x),
                                              let snapped = nearestTime(to: rawTime, in: baseTimeline) else {
                                            selectedTime = nil
                                            return
                                        }
                                        selectedTime = snapped
                                    }
                                    .onEnded { _ in
                                        selectedTime = nil
                                    }
                            )
                            .onHover { hovering in
                                if !hovering {
                                    selectedTime = nil
                                }
                            }

                        // Tooltip on hover/drag
                        if let selectedTime,
                           let xPos = proxy.position(forX: selectedTime) {
                            let clampedX = min(max(xPos, 0), geo.size.width)

                            let values = buildSeriesValues(
                                at: selectedTime,
                                memoryData: memoryData,
                                cpuData: cpuData,
                                systemCpuData: systemCpuData,
                                perCoreData: perCoreData
                            )

                            // Tooltip card
                            VStack(alignment: .leading, spacing: 8) {
                                // Time header
                                HStack {
                                    Image(systemName: "clock")
                                        .font(.system(size: 9))
                                        .foregroundColor(PremiumColors.textSubtle)
                                    Text(selectedTime, style: .time)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(PremiumColors.textSecondary)
                                }

                                Divider()
                                    .background(Color.white.opacity(0.08))

                                // RAM value (always show first)
                                if let ramValue = values.first(where: { $0.label == "RAM" }) {
                                    HStack(spacing: 8) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(ramValue.color)
                                            .frame(width: 3, height: 16)
                                        Text(ramValue.label)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(PremiumColors.textSecondary)
                                        Spacer()
                                        Text(ramValue.value)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                }

                                // CPU cores in a compact grid
                                let coreValues = values.filter { $0.label.hasPrefix("Core") }
                                if !coreValues.isEmpty {
                                    Divider()
                                        .background(Color.white.opacity(0.06))

                                    Text("CPU CORES")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundColor(PremiumColors.textSubtle)
                                        .tracking(0.5)

                                    let columns = min(4, max(2, (coreValues.count + 1) / 2))
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                                        ForEach(coreValues) { item in
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(item.color)
                                                    .frame(width: 6, height: 6)
                                                Text(item.value)
                                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(.white.opacity(0.9))
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                } else {
                                    // Single CPU value
                                    let cpuValue = values.first(where: { $0.label.contains("CPU") })
                                    if let cpu = cpuValue {
                                        HStack(spacing: 8) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(cpu.color)
                                                .frame(width: 3, height: 16)
                                            Text(cpu.label)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(PremiumColors.textSecondary)
                                            Spacer()
                                            Text(cpu.value)
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                            .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                            .frame(width: 180)
                            .position(x: min(max(clampedX, 100), geo.size.width - 100), y: 80)
                        }
                    }
                }
                .frame(height: 180)
                .padding(.bottom, PremiumMetrics.innerSpacing)

                // Legend row - compact, elegant
                HStack(spacing: 16) {
                    // RAM legend
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PremiumColors.violet)
                            .frame(width: 12, height: 3)
                        Text("Memory")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PremiumColors.textMuted)
                    }

                    // CPU cores legend
                    if !perCoreData.isEmpty {
                        HStack(spacing: 6) {
                            // Show color gradient for cores
                            HStack(spacing: 1) {
                                ForEach(0..<min(perCoreData.count, 6), id: \.self) { i in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(coreColor(i, total: perCoreData.count))
                                        .frame(width: 3, height: 8)
                                }
                                if perCoreData.count > 6 {
                                    Text("…")
                                        .font(.system(size: 8))
                                        .foregroundColor(PremiumColors.textSubtle)
                                }
                            }
                            Text("\(perCoreData.count) CPU Cores")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(PremiumColors.textMuted)
                        }
                    } else if !cpuData.isEmpty || !systemCpuData.isEmpty {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PremiumColors.indigo)
                                .frame(width: 12, height: 3)
                            Text("CPU")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(PremiumColors.textMuted)
                        }
                    }

                    Spacer()

                    // Current values (live)
                    if let lastMem = memoryData.last {
                        Text(String(format: "RAM: %.0f%%", lastMem.value))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(PremiumColors.violet)
                    }

                    if !perCoreData.isEmpty {
                        let avgCpu = perCoreData.compactMap { $0.last?.value }.reduce(0, +) / Double(max(perCoreData.count, 1))
                        Text(String(format: "CPU Avg: %.0f%%", avgCpu))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(PremiumColors.indigo)
                    } else if let lastCpu = cpuData.last ?? systemCpuData.last {
                        Text(String(format: "CPU: %.0f%%", lastCpu.value))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(PremiumColors.indigo)
                    }
                }
            } else {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 28))
                            .foregroundColor(PremiumColors.textSubtle)
                        Text("Collecting data…")
                            .font(.system(size: 11))
                            .foregroundColor(PremiumColors.textMuted)
                    }
                    .padding(.vertical, 40)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Player Grid View

struct PlayerGridView: View {
    let players: [PlayersUpdatePayload.PlayerInfo]

    let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(players, id: \.uuid) { player in
                PlayerCard(player: player)
            }
        }
    }
}

struct PlayerCard: View {
    let player: PlayersUpdatePayload.PlayerInfo
    @State private var isHovered = false

    // Crafatar requires UUID without dashes
    private var cleanUUID: String {
        player.uuid.replacingOccurrences(of: "-", with: "")
    }

    private var avatarURL: URL? {
        URL(string: "https://crafatar.com/avatars/\(cleanUUID)?size=64&overlay")
    }

    var body: some View {
        HStack(spacing: PremiumMetrics.innerSpacing) {
            // Player avatar (Crafatar head)
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                case .failure:
                    // Fallback to Steve head silhouette
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PremiumColors.indigo.opacity(0.2))
                        Image(systemName: "person.fill")
                            .font(.system(size: 16))
                            .foregroundColor(PremiumColors.indigo.opacity(0.6))
                    }
                case .empty:
                    // Loading state
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.05))
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PremiumColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // World with icon
                    HStack(spacing: 3) {
                        Image(systemName: "globe")
                            .font(.system(size: 8))
                            .foregroundColor(PremiumColors.textSubtle)
                        Text(player.world)
                            .font(PremiumTypography.caption)
                            .foregroundColor(PremiumColors.textMuted)
                            .lineLimit(1)
                    }

                    // Ping indicator
                    HStack(spacing: 3) {
                        Circle()
                            .fill(pingColor(player.ping))
                            .frame(width: 5, height: 5)
                        Text("\(player.ping)ms")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(PremiumColors.textMuted)
                    }
                }
            }

            Spacer()
        }
        .padding(PremiumMetrics.innerSpacing)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.12 : 0.06), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func pingColor(_ ping: Int) -> Color {
        if ping < 80 { return PremiumColors.emerald }
        if ping < 150 { return PremiumColors.amber }
        return PremiumColors.rose
    }
}

// MARK: - Basic Info Card (for no-bridge state)

struct BasicInfoCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(color.opacity(0.2), lineWidth: 1)
                        }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.3)

                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Trend Direction

enum TrendDirection {
    case up, down, stable

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: return Color(hex: "22C55E")
        case .down: return Color(hex: "EF4444")
        case .stable: return Color.white.opacity(0.5)
        }
    }
}

// MARK: - Primary Metric Card (Large, with sparkline and trend)

struct PrimaryMetricCard: View {
    let title: String
    let value: String
    let maxValue: String
    let icon: String
    let color: Color
    var sparklineData: [Double] = []
    var chartMaxValue: Double = 100
    var trend: TrendDirection = .stable

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)

                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                // Trend indicator
                HStack(spacing: 3) {
                    Image(systemName: trend.icon)
                        .font(.system(size: 9, weight: .bold))
                    Text(trend == .stable ? "Stable" : (trend == .up ? "Rising" : "Falling"))
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(trend.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(trend.color.opacity(0.15))
                }
            }
            .padding(.bottom, 12)

            // Value row
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("/ \(maxValue)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.bottom, 12)

            // Sparkline
            if !sparklineData.isEmpty {
                SparklineView(data: sparklineData, color: color, maxValue: chartMaxValue)
                    .frame(height: 40)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 40)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Memory Metric Card (with detailed breakdown)

struct MemoryMetricCard: View {
    let usedMB: Int64
    let maxMB: Int64
    let color: Color

    @State private var isHovered = false

    private var usedGB: Double { Double(usedMB) / 1024.0 }
    private var maxGB: Double { Double(maxMB) / 1024.0 }
    private var percentage: Double { Double(usedMB) / Double(max(maxMB, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "memorychip.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(color)

                    Text("Memory")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                Text("\(Int(percentage * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            .padding(.bottom, 10)

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.2f", usedGB))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("GB")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Text("/ \(String(format: "%.1f", maxGB)) GB")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.bottom, 10)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(percentage, 1.0))
                }
            }
            .frame(height: 8)
            .padding(.bottom, 8)

            // Detailed breakdown
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text("Used: \(usedMB) MB")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                    Text("Free: \(maxMB - usedMB) MB")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Players Metric Card

struct PlayersMetricCard: View {
    let current: Int
    let max: Int
    var sparklineData: [Double] = []

    @State private var isHovered = false

    private var percentage: Double { Double(current) / Double(Swift.max(max, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)

                    Text("Players")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                if current > 0 {
                    Text("Online")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "22C55E"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(Color(hex: "22C55E").opacity(0.15))
                        }
                }
            }
            .padding(.bottom, 10)

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(current)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("/ \(max)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.bottom, 10)

            // Mini sparkline
            if !sparklineData.isEmpty {
                SparklineView(data: sparklineData, color: .blue, maxValue: Double(max))
                    .frame(height: 24)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 24)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.blue.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Uptime Badge (compact, for server header)

struct UptimeBadge: View {
    let seconds: Int64

    private var formattedUptime: String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text(formattedUptime)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.6))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

// MARK: - Player Count Badge (compact, for server header)

struct PlayerCountBadge: View {
    let count: Int
    let max: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.system(size: 9))
            Text("\(count)/\(max)")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(count > 0 ? .blue : .white.opacity(0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(count > 0 ? Color.blue.opacity(0.15) : Color.white.opacity(0.1)))
    }
}

// MARK: - Tick Health Indicator

struct TickHealthIndicator: View {
    let tps: Double?
    let mspt: Double?

    private var health: (text: String, color: Color) {
        guard let tps = tps else { return ("--", .gray) }
        if tps >= 19.5 && (mspt ?? 0) < 40 {
            return ("Excellent", Color(hex: "22C55E"))
        }
        if tps >= 18 && (mspt ?? 0) < 50 {
            return ("Good", Color(hex: "22C55E"))
        }
        if tps >= 15 {
            return ("Fair", Color(hex: "EAB308"))
        }
        return ("Poor", Color(hex: "EF4444"))
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(health.color)
                .frame(width: 6, height: 6)
            Text(health.text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(health.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(health.color.opacity(0.15)))
    }
}

// MARK: - Dual Sparkline View (TPS + MSPT overlay)

struct DualSparklineView: View {
    let primaryData: [Double]
    let secondaryData: [Double]
    let primaryColor: Color
    let secondaryColor: Color
    let primaryMax: Double
    let secondaryMax: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Secondary line (MSPT) - behind, dashed
                if secondaryData.count > 1 {
                    Path { path in
                        for (index, value) in secondaryData.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(secondaryData.count - 1)
                            let normalizedValue = value / secondaryMax
                            let y = geometry.size.height * (1 - CGFloat(min(normalizedValue, 1.0)))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(secondaryColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                // Primary line (TPS) - in front, solid
                if primaryData.count > 1 {
                    Path { path in
                        for (index, value) in primaryData.enumerated() {
                            let x = geometry.size.width * CGFloat(index) / CGFloat(primaryData.count - 1)
                            let normalizedValue = value / primaryMax
                            let y = geometry.size.height * (1 - CGFloat(min(normalizedValue, 1.0)))

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [primaryColor.opacity(0.6), primaryColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                }

                // Reference line at top (TPS 20)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: 0))
                }
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }
}

// MARK: - Tick Performance Card (merged TPS + MSPT)

struct TickPerformanceCard: View {
    let tps: Double?
    let mspt: Double?
    let tpsHistory: [PerformanceHistory.DataPoint]
    let msptHistory: [PerformanceHistory.DataPoint]

    @State private var isHovered = false

    private var tpsColor: Color {
        guard let tps = tps else { return .gray }
        if tps >= 18 { return Color(hex: "22C55E") }
        if tps >= 15 { return Color(hex: "EAB308") }
        return Color(hex: "EF4444")
    }

    private var msptColor: Color {
        guard let mspt = mspt else { return .gray }
        if mspt < 40 { return Color(hex: "22C55E") }
        if mspt < 50 { return Color(hex: "EAB308") }
        return Color(hex: "EF4444")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tpsColor)

                    Text("TICK PERFORMANCE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                TickHealthIndicator(tps: tps, mspt: mspt)
            }
            .padding(.bottom, 12)

            // Main metrics row
            HStack(alignment: .bottom, spacing: 20) {
                // TPS - Primary (large)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TPS")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(tps.map { String(format: "%.2f", $0) } ?? "--")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("/ 20")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1, height: 50)

                // MSPT - Secondary (smaller)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MSPT")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(mspt.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(msptColor)

                        Text("ms")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }

                    Text(mspt.map { $0 < 50 ? "< 50ms target" : "Above target" } ?? "")
                        .font(.system(size: 9))
                        .foregroundColor(msptColor.opacity(0.7))
                }

                Spacer()
            }
            .padding(.bottom, 16)

            // Dual sparkline
            DualSparklineView(
                primaryData: tpsHistory.suffix(60).map { $0.value },
                secondaryData: msptHistory.suffix(60).map { $0.value },
                primaryColor: tpsColor,
                secondaryColor: msptColor,
                primaryMax: 20,
                secondaryMax: 100
            )
            .frame(height: 48)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tpsColor.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Gotop Resource Bar (historical mini-bars + current value)

struct GotopResourceBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let displayValue: String
    let displayMax: String?
    let color: Color
    let history: [Double]

    private var percentage: Double {
        value / max(maxValue, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label row
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                HStack(spacing: 4) {
                    Text(displayValue)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)

                    if let displayMax = displayMax {
                        Text("/")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                        Text(displayMax)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(String(format: "%.0f%%", percentage * 100))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            // Gotop-style bar with history segments
            GeometryReader { geo in
                HStack(spacing: 1) {
                    // Historical bars (mini bar chart)
                    ForEach(Array(history.enumerated()), id: \.offset) { index, histValue in
                        let barPercent = histValue / max(maxValue, 1)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color.opacity(0.3 + (Double(index) / Double(max(history.count, 1))) * 0.4))
                            .frame(height: geo.size.height * min(barPercent, 1.0))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }

                    // Current value bar (brighter)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 4, height: geo.size.height * min(percentage, 1.0))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }
}

struct GotopResourceBarPlaceholder: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                Text("N/A")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.05))
                .frame(height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

// MARK: - Resource Monitor Card (Memory + CPU gotop-style)

struct ResourceMonitorCard: View {
    let usedMemoryMB: Int64
    let maxMemoryMB: Int64
    let cpuPercent: Double?
    let systemCpuPercent: Double?
    let threadCount: Int?
    let memoryHistory: [PerformanceHistory.DataPoint]
    let cpuHistory: [PerformanceHistory.DataPoint]

    @State private var isHovered = false

    private var memoryPercent: Double {
        Double(usedMemoryMB) / Double(max(maxMemoryMB, 1))
    }

    private var memoryColor: Color {
        if memoryPercent < 0.7 { return Color(hex: "22C55E") }
        if memoryPercent < 0.85 { return Color(hex: "EAB308") }
        return Color(hex: "EF4444")
    }

    private var cpuColor: Color {
        guard let cpu = displayCpuPercent else { return .gray }
        if cpu < 50 { return Color(hex: "3B82F6") }  // Blue
        if cpu < 80 { return Color(hex: "EAB308") }
        return Color(hex: "EF4444")
    }

    private var displayCpuPercent: Double? {
        cpuPercent ?? systemCpuPercent
    }

    private var cpuLabel: String {
        if cpuPercent != nil { return "CPU" }
        if systemCpuPercent != nil { return "CPU (SYS)" }
        return "CPU"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.blue)

                    Text("RESOURCES")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()

                // Thread count badge
                if let threads = threadCount {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                        Text("\(threads) threads")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.bottom, 16)

            // Memory bar
            GotopResourceBar(
                label: "MEM",
                value: Double(usedMemoryMB),
                maxValue: Double(maxMemoryMB),
                displayValue: String(format: "%.2f GB", Double(usedMemoryMB) / 1024),
                displayMax: String(format: "%.1f GB", Double(maxMemoryMB) / 1024),
                color: memoryColor,
                history: memoryHistory.suffix(30).map { $0.value }
            )
            .padding(.bottom, 12)

            // CPU bar (if available)
            if let cpu = displayCpuPercent {
                GotopResourceBar(
                    label: cpuLabel,
                    value: cpu,
                    maxValue: 100,
                    displayValue: String(format: "%.1f%%", cpu),
                    displayMax: nil,
                    color: cpuColor,
                    history: cpuHistory.suffix(30).map { $0.value }
                )
            } else {
                // CPU not available placeholder
                GotopResourceBarPlaceholder(label: "CPU")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.blue.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Clickable Player Indicator (expandable)

struct ClickablePlayerIndicator: View {
    let playerCount: Int
    let maxPlayers: Int
    let players: [PlayersUpdatePayload.PlayerInfo]
    let sparklineData: [Double]

    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            let hasPlayers = !players.isEmpty
            let isWaitingForPlayers = playerCount > 0 && !hasPlayers

            // Clickable header
            Button(action: { withAnimation(.spring()) { isExpanded.toggle() } }) {
                HStack(spacing: 16) {
                    // Player icon with count
                    ZStack {
                        Circle()
                            .fill(playerCount > 0 ? Color.blue.opacity(0.2) : Color.white.opacity(0.1))
                            .frame(width: 48, height: 48)

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 20))
                            .foregroundColor(playerCount > 0 ? .blue : .white.opacity(0.4))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("ONLINE PLAYERS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(.uppercase)
                            .tracking(0.5)

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(playerCount)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("/ \(maxPlayers)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }

                    Spacer()

                    // Mini sparkline
                    if !sparklineData.isEmpty {
                        SparklineView(data: sparklineData, color: .blue, maxValue: Double(maxPlayers))
                            .frame(width: 80, height: 32)
                    }

                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable player grid
            if isExpanded && hasPlayers {
                Divider()
                    .background(Color.white.opacity(0.1))

                PlayerGridView(players: players)
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isExpanded && isWaitingForPlayers {
                Divider()
                    .background(Color.white.opacity(0.1))

                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        Text("Loading player list…")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .transition(.opacity)
            } else if isExpanded && !hasPlayers {
                Divider()
                    .background(Color.white.opacity(0.1))

                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No players online")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.blue.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.003 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - System Info Badge (compact, for header)

struct SystemInfoBadge: View {
    let systemInfo: SystemInfoPayload?

    var body: some View {
        if let info = systemInfo {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                Text(truncatedCpuModel(info.cpuModel))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                Text("•")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.3))
                Text("\(info.cpuCores) cores")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
    }

    private func truncatedCpuModel(_ model: String) -> String {
        // Truncate long CPU names (e.g., "AMD Ryzen 9 5900X 12-Core Processor" -> "Ryzen 9 5900X")
        if model.lowercased().contains("ryzen") {
            if let range = model.range(of: "Ryzen", options: .caseInsensitive) {
                let start = range.lowerBound
                let rest = model[start...]
                let parts = rest.split(separator: " ").prefix(3)
                return parts.joined(separator: " ")
            }
        }
        if model.lowercased().contains("intel") || model.lowercased().contains("core") {
            // Intel Core i7-12700K -> "i7-12700K"
            if let match = model.range(of: "i[3579]-\\S+", options: .regularExpression) {
                return String(model[match])
            }
        }
        // Apple Silicon
        if model.contains("Apple") {
            return model.replacingOccurrences(of: "Apple ", with: "")
        }
        // Fallback: first 20 chars
        if model.count > 20 {
            return String(model.prefix(20)) + "…"
        }
        return model
    }
}

// MARK: - Disk Usage Card (gotop-style)

struct DiskUsageCard: View {
    let disks: [DiskInfo]?
    let history: [PerformanceHistory.DataPoint]

    @State private var isHovered = false

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1000 {
            return String(format: "%.1f TB", gb / 1024)
        } else if gb >= 100 {
            return String(format: "%.0f GB", gb)
        } else if gb >= 10 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.2f GB", gb)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.orange)

                    Text("DISK")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()
            }
            .padding(.bottom, 12)

            // Disk bars
            if let disks = disks, !disks.isEmpty {
                VStack(spacing: 8) {
                    ForEach(disks.prefix(3), id: \.mount) { disk in
                        DiskBarRow(disk: disk)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Text("N/A")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.003 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct DiskBarRow: View {
    let disk: DiskInfo

    private var color: Color {
        if disk.usagePercent < 70 { return Color(hex: "22C55E") }
        if disk.usagePercent < 85 { return Color(hex: "EAB308") }
        return Color(hex: "EF4444")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 100 {
            return String(format: "%.0fG", gb)
        } else if gb >= 10 {
            return String(format: "%.1fG", gb)
        } else {
            return String(format: "%.2fG", gb)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(disk.mount)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                HStack(spacing: 4) {
                    Text(formatBytes(disk.usedBytes))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                    Text("/")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                    Text(formatBytes(disk.totalBytes))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text(String(format: "%.0f%%", disk.usagePercent))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * min(disk.usagePercent / 100, 1.0))
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Network Usage Card (gotop-style)

struct NetworkUsageCard: View {
    let network: NetworkInfo?
    let rxHistory: [PerformanceHistory.DataPoint]
    let txHistory: [PerformanceHistory.DataPoint]

    @State private var isHovered = false

    private func formatRate(_ bytesPerSec: Int64) -> String {
        if bytesPerSec >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB/s", Double(bytesPerSec) / (1024 * 1024 * 1024))
        } else if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1f MB/s", Double(bytesPerSec) / (1024 * 1024))
        } else if bytesPerSec >= 1024 {
            return String(format: "%.1f KB/s", Double(bytesPerSec) / 1024)
        } else {
            return String(format: "%d B/s", bytesPerSec)
        }
    }

    private func formatTotal(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 100 {
            return String(format: "%.0f GB", gb)
        } else if gb >= 10 {
            return String(format: "%.1f GB", gb)
        } else if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else {
            return String(format: "%.0f MB", Double(bytes) / (1024 * 1024))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.cyan)

                    Text("NETWORK")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()
            }
            .padding(.bottom, 12)

            if let net = network {
                VStack(spacing: 10) {
                    // RX (download)
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                            Text("Rx")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 40, alignment: .leading)

                        Text(formatTotal(net.rxBytes))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))

                        Spacer()

                        Text(formatRate(net.rxBytesPerSec))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    // TX (upload)
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                            Text("Tx")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 40, alignment: .leading)

                        Text(formatTotal(net.txBytes))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))

                        Spacer()

                        Text(formatRate(net.txBytesPerSec))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }

                    // Mini sparklines
                    if !rxHistory.isEmpty || !txHistory.isEmpty {
                        NetworkSparkline(
                            rxData: rxHistory.suffix(30).map { $0.value },
                            txData: txHistory.suffix(30).map { $0.value }
                        )
                        .frame(height: 24)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Text("N/A")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.cyan.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.003 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct NetworkSparkline: View {
    let rxData: [Double]
    let txData: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(
                rxData.max() ?? 1,
                txData.max() ?? 1,
                1
            )

            ZStack {
                // RX line (green)
                if rxData.count > 1 {
                    Path { path in
                        for (index, value) in rxData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(rxData.count - 1)
                            let y = geo.size.height * (1 - CGFloat(value / maxVal))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.green.opacity(0.6), lineWidth: 1.5)
                }

                // TX line (blue)
                if txData.count > 1 {
                    Path { path in
                        for (index, value) in txData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(txData.count - 1)
                            let y = geo.size.height * (1 - CGFloat(value / maxVal))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue.opacity(0.6), lineWidth: 1.5)
                }
            }
        }
    }
}

// MARK: - Premium Tick Performance Card

struct PremiumTickPerformanceCard: View {
    let tps: Double?
    let mspt: Double?
    let tpsHistory: [PerformanceHistory.DataPoint]
    let msptHistory: [PerformanceHistory.DataPoint]

    @State private var isHovered = false
    @State private var appeared = false

    private var tpsColor: Color { PremiumColors.tpsColor(tps) }
    private var msptColor: Color { PremiumColors.msptColor(mspt) }

    private var healthStatus: (text: String, color: Color) {
        guard let tps = tps else { return ("Unknown", PremiumColors.slate) }
        if tps >= 19.5 { return ("Excellent", PremiumColors.emerald) }
        if tps >= 18 { return ("Good", Color(hex: "84CC16")) }
        if tps >= 15 { return ("Fair", PremiumColors.amber) }
        return ("Poor", PremiumColors.rose)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with status pill
            HStack {
                HStack(spacing: PremiumMetrics.tightSpacing) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: PremiumMetrics.iconSizeSmall, weight: .semibold))
                        .foregroundColor(tpsColor)

                    Text("TICK PERFORMANCE")
                        .font(PremiumTypography.sectionHeader)
                        .foregroundColor(PremiumColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                Spacer()

                // Status pill
                Text(healthStatus.text)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(healthStatus.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(healthStatus.color.opacity(0.15))
                            .overlay {
                                Capsule()
                                    .stroke(healthStatus.color.opacity(0.3), lineWidth: 1)
                            }
                    }
            }
            .padding(.bottom, PremiumMetrics.innerSpacing)

            // Main metrics row
            HStack(alignment: .bottom, spacing: 24) {
                // TPS - Hero metric
                VStack(alignment: .leading, spacing: 2) {
                    Text("TPS")
                        .font(PremiumTypography.label)
                        .foregroundColor(PremiumColors.textMuted)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(tps.map { String(format: "%.2f", $0) } ?? "--")
                            .font(PremiumTypography.heroValue)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        Text("/ 20")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(PremiumColors.textSubtle)
                    }
                }

                // Elegant vertical divider
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.02), Color.white.opacity(0.12), Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 1, height: 56)

                // MSPT - Secondary metric
                VStack(alignment: .leading, spacing: 2) {
                    Text("MSPT")
                        .font(PremiumTypography.label)
                        .foregroundColor(PremiumColors.textMuted)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(mspt.map { String(format: "%.1f", $0) } ?? "--")
                            .font(PremiumTypography.largeValue)
                            .foregroundColor(msptColor)

                        Text("ms")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(PremiumColors.textSubtle)
                    }

                    // Target indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(msptColor)
                            .frame(width: 6, height: 6)
                        Text(mspt.map { $0 < 50 ? "Under 50ms target" : "Above target" } ?? "")
                            .font(PremiumTypography.caption)
                            .foregroundColor(PremiumColors.textMuted)
                    }
                }

                Spacer()
            }
            .padding(.bottom, PremiumMetrics.innerSpacing + 4)

            // Premium dual sparkline
            PremiumDualSparkline(
                primaryData: tpsHistory.suffix(60).map { $0.value },
                secondaryData: msptHistory.suffix(60).map { $0.value },
                primaryColor: tpsColor,
                secondaryColor: msptColor.opacity(0.6),
                primaryMax: 20,
                secondaryMax: 100
            )
            .frame(height: PremiumMetrics.sparklineHeight)
        }
        .padding(PremiumMetrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: PremiumMetrics.primaryCardMinHeight, alignment: .top)
        .equalHeight()
        .background { PremiumCardBackground(accentColor: tpsColor, isHovered: isHovered) }
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.easeOut(duration: 0.4), value: appeared)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
    }
}

// MARK: - Premium Resource Monitor Card

struct PremiumResourceMonitorCard: View {
    let usedMemoryMB: Int64
    let maxMemoryMB: Int64
    let cpuPercent: Double?
    let systemCpuPercent: Double?
    let threadCount: Int?
    let cpuModel: String?
    let cpuCores: Int?
    let memoryHistory: [PerformanceHistory.DataPoint]
    let cpuHistory: [PerformanceHistory.DataPoint]

    @State private var isHovered = false
    @State private var appeared = false

    private var memoryPercent: Double {
        Double(usedMemoryMB) / Double(max(maxMemoryMB, 1))
    }

    private var memoryColor: Color { PremiumColors.memoryColor(memoryPercent) }

    private var displayCpuPercent: Double? { cpuPercent ?? systemCpuPercent }

    private var cpuColor: Color {
        guard let cpu = displayCpuPercent else { return PremiumColors.slate }
        return PremiumColors.cpuColor(cpu)
    }

    private var cpuLabel: String {
        if cpuPercent != nil { return "CPU" }
        if systemCpuPercent != nil { return "SYS CPU" }
        return "CPU"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with CPU info
            HStack {
                HStack(spacing: PremiumMetrics.tightSpacing) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: PremiumMetrics.iconSizeSmall, weight: .semibold))
                        .foregroundColor(PremiumColors.indigo)

                    Text("RESOURCES")
                        .font(PremiumTypography.sectionHeader)
                        .foregroundColor(PremiumColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                Spacer()

                // Thread count + CPU model badge
                HStack(spacing: 8) {
                    if let threads = threadCount {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text("\(threads)")
                                .font(PremiumTypography.monoSmall)
                        }
                        .foregroundColor(PremiumColors.textMuted)
                    }

                    if let cpuModel = cpuModel, let cores = cpuCores {
                        Text("\(formatCpuModel(cpuModel)) • \(cores)c")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(PremiumColors.textSubtle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                            }
                    }
                }
            }
            .padding(.bottom, PremiumMetrics.innerSpacing + 4)

            // Memory resource bar
            PremiumResourceBar(
                label: "MEMORY",
                value: Double(usedMemoryMB),
                maxValue: Double(maxMemoryMB),
                displayValue: formatMemory(usedMemoryMB),
                displayMax: formatMemory(maxMemoryMB),
                color: memoryColor,
                history: memoryHistory.suffix(30).map { $0.value }
            )
            .padding(.bottom, PremiumMetrics.innerSpacing)

            // CPU resource bar
            if let cpu = displayCpuPercent {
                PremiumResourceBar(
                    label: cpuLabel,
                    value: cpu,
                    maxValue: 100,
                    displayValue: String(format: "%.1f%%", cpu),
                    displayMax: nil,
                    color: cpuColor,
                    history: cpuHistory.suffix(30).map { $0.value }
                )
            } else {
                PremiumResourceBarPlaceholder(label: "CPU")
            }
        }
        .padding(PremiumMetrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: PremiumMetrics.primaryCardMinHeight, alignment: .top)
        .equalHeight()
        .background { PremiumCardBackground(accentColor: PremiumColors.indigo, isHovered: isHovered) }
        .scaleEffect(isHovered ? 1.008 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.easeOut(duration: 0.4).delay(0.05), value: appeared)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
    }

    private func formatMemory(_ mb: Int64) -> String {
        let gb = Double(mb) / 1024.0
        if gb >= 10 {
            return String(format: "%.1f GB", gb)
        }
        return String(format: "%.2f GB", gb)
    }

    private func formatCpuModel(_ model: String) -> String {
        // Truncate long CPU names elegantly
        if model.lowercased().contains("ryzen") {
            if let range = model.range(of: "Ryzen", options: .caseInsensitive) {
                let rest = model[range.lowerBound...]
                let parts = rest.split(separator: " ").prefix(3)
                return parts.joined(separator: " ")
            }
        }
        if model.lowercased().contains("core") {
            if let match = model.range(of: "i[3579]-\\S+", options: .regularExpression) {
                return String(model[match])
            }
        }
        if model.contains("Apple") {
            return model.replacingOccurrences(of: "Apple ", with: "")
        }
        if model.count > 18 {
            return String(model.prefix(18)) + "…"
        }
        return model
    }
}

// MARK: - Premium Resource Bar (Clean Progress Style)

struct PremiumResourceBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let displayValue: String
    let displayMax: String?
    let color: Color
    let history: [Double]  // Kept for API compatibility but not displayed

    private var percentage: Double {
        value / max(maxValue, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PremiumMetrics.tightSpacing) {
            // Label row with values
            HStack {
                Text(label)
                    .font(PremiumTypography.monoSmall)
                    .foregroundColor(PremiumColors.textMuted)

                Spacer()

                HStack(spacing: 6) {
                    Text(displayValue)
                        .font(PremiumTypography.monoMedium)
                        .foregroundColor(PremiumColors.textPrimary)

                    if let displayMax = displayMax {
                        Text("/")
                            .font(.system(size: 10))
                            .foregroundColor(PremiumColors.textSubtle)
                        Text(displayMax)
                            .font(PremiumTypography.monoSmall)
                            .foregroundColor(PremiumColors.textMuted)
                    }
                }
            }

            // Clean progress bar with percentage inside
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.06))

                    // Filled portion with gradient
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(percentage, 1.0))
                        .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 0)

                    // Percentage label centered in the bar
                    HStack {
                        Spacer()
                        Text(String(format: "%.0f%%", percentage * 100))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        Spacer()
                    }
                }
            }
            .frame(height: 28)
        }
    }
}

struct PremiumResourceBarPlaceholder: View {
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: PremiumMetrics.tightSpacing) {
            HStack {
                Text(label)
                    .font(PremiumTypography.monoSmall)
                    .foregroundColor(PremiumColors.textSubtle)

                Spacer()

                Text("N/A")
                    .font(PremiumTypography.monoSmall)
                    .foregroundColor(PremiumColors.textSubtle)
            }

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
                .frame(height: 28)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
                .overlay {
                    Text("Not available")
                        .font(PremiumTypography.caption)
                        .foregroundColor(PremiumColors.textSubtle)
                }
        }
    }
}

// MARK: - Premium Disk Usage Card

struct PremiumDiskUsageCard: View {
    let disks: [DiskInfo]?
    let history: [PerformanceHistory.DataPoint]

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: PremiumMetrics.tightSpacing) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: PremiumMetrics.iconSizeSmall, weight: .semibold))
                        .foregroundColor(PremiumColors.amber)

                    Text("STORAGE")
                        .font(PremiumTypography.sectionHeader)
                        .foregroundColor(PremiumColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                Spacer()

                // Total storage summary
                if let disks = disks, !disks.isEmpty {
                    let totalUsed = disks.reduce(0) { $0 + $1.usedBytes }
                    let totalSize = disks.reduce(0) { $0 + $1.totalBytes }
                    Text("\(formatBytes(totalUsed)) / \(formatBytes(totalSize))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(PremiumColors.textSubtle)
                }
            }
            .padding(.bottom, PremiumMetrics.innerSpacing)

            // Disk entries with circular indicators
            if let disks = disks, !disks.isEmpty {
                VStack(spacing: PremiumMetrics.innerSpacing) {
                    ForEach(disks.prefix(3), id: \.mount) { disk in
                        PremiumDiskRow(disk: disk)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .font(.system(size: 24))
                            .foregroundColor(PremiumColors.textSubtle)
                        Text("No disk data")
                            .font(PremiumTypography.caption)
                            .foregroundColor(PremiumColors.textMuted)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            }
        }
        .padding(PremiumMetrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: PremiumMetrics.secondaryCardMinHeight, alignment: .top)
        .equalHeight()
        .background { PremiumCardBackground(accentColor: PremiumColors.amber, isHovered: isHovered) }
        .scaleEffect(isHovered ? 1.006 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1000 {
            return String(format: "%.1f TB", gb / 1024)
        } else if gb >= 100 {
            return String(format: "%.0f GB", gb)
        } else if gb >= 10 {
            return String(format: "%.1f GB", gb)
        }
        return String(format: "%.2f GB", gb)
    }
}

struct PremiumDiskRow: View {
    let disk: DiskInfo

    private var color: Color { PremiumColors.diskColor(disk.usagePercent) }

    var body: some View {
        HStack(spacing: PremiumMetrics.innerSpacing) {
            // Circular progress indicator
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                    .frame(width: 36, height: 36)

                Circle()
                    .trim(from: 0, to: disk.usagePercent / 100)
                    .stroke(
                        LinearGradient(
                            colors: [color.opacity(0.7), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))

                Text(String(format: "%.0f", disk.usagePercent))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(disk.mount)
                    .font(PremiumTypography.monoSmall)
                    .foregroundColor(PremiumColors.textSecondary)

                Text("\(formatBytes(disk.usedBytes)) of \(formatBytes(disk.totalBytes))")
                    .font(PremiumTypography.caption)
                    .foregroundColor(PremiumColors.textMuted)
            }

            Spacer()

            // Free space indicator
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(disk.totalBytes - disk.usedBytes))
                    .font(PremiumTypography.monoMedium)
                    .foregroundColor(PremiumColors.textPrimary)
                Text("free")
                    .font(PremiumTypography.caption)
                    .foregroundColor(PremiumColors.textSubtle)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1000 {
            return String(format: "%.1f TB", gb / 1024)
        } else if gb >= 100 {
            return String(format: "%.0f GB", gb)
        } else if gb >= 10 {
            return String(format: "%.1f GB", gb)
        }
        return String(format: "%.2f GB", gb)
    }
}

// MARK: - Premium Network Usage Card

struct PremiumNetworkUsageCard: View {
    let network: NetworkInfo?
    let rxHistory: [PerformanceHistory.DataPoint]
    let txHistory: [PerformanceHistory.DataPoint]

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: PremiumMetrics.tightSpacing) {
                    Image(systemName: "network")
                        .font(.system(size: PremiumMetrics.iconSizeSmall, weight: .semibold))
                        .foregroundColor(PremiumColors.teal)

                    Text("NETWORK")
                        .font(PremiumTypography.sectionHeader)
                        .foregroundColor(PremiumColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1.2)
                }

                Spacer()

                // Peak rate indicator (if we have history)
                if let maxRx = rxHistory.map({ $0.value }).max(),
                   let maxTx = txHistory.map({ $0.value }).max() {
                    let peak = max(maxRx, maxTx)
                    if peak > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 8))
                            Text("Peak: \(formatRate(Int64(peak)))")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(PremiumColors.textSubtle)
                    }
                }
            }
            .padding(.bottom, PremiumMetrics.innerSpacing)

            if let net = network {
                VStack(spacing: PremiumMetrics.innerSpacing) {
                    // Download row
                    HStack {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(PremiumColors.emerald.opacity(0.15))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(PremiumColors.emerald)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Download")
                                    .font(PremiumTypography.label)
                                    .foregroundColor(PremiumColors.textMuted)
                                Text(formatTotal(net.rxBytes))
                                    .font(PremiumTypography.caption)
                                    .foregroundColor(PremiumColors.textSubtle)
                            }
                        }

                        Spacer()

                        Text(formatRate(net.rxBytesPerSec))
                            .font(PremiumTypography.monoLarge)
                            .foregroundColor(PremiumColors.emerald)
                    }

                    // Upload row
                    HStack {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(PremiumColors.sky.opacity(0.15))
                                    .frame(width: 24, height: 24)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(PremiumColors.sky)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Upload")
                                    .font(PremiumTypography.label)
                                    .foregroundColor(PremiumColors.textMuted)
                                Text(formatTotal(net.txBytes))
                                    .font(PremiumTypography.caption)
                                    .foregroundColor(PremiumColors.textSubtle)
                            }
                        }

                        Spacer()

                        Text(formatRate(net.txBytesPerSec))
                            .font(PremiumTypography.monoLarge)
                            .foregroundColor(PremiumColors.sky)
                    }

                    // Enhanced sparkline
                    if !rxHistory.isEmpty || !txHistory.isEmpty {
                        PremiumNetworkSparkline(
                            rxData: rxHistory.suffix(30).map { $0.value },
                            txData: txHistory.suffix(30).map { $0.value }
                        )
                        .frame(height: PremiumMetrics.miniSparklineHeight)
                        .padding(.top, 4)
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 24))
                            .foregroundColor(PremiumColors.textSubtle)
                        Text("No network data")
                            .font(PremiumTypography.caption)
                            .foregroundColor(PremiumColors.textMuted)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            }
        }
        .padding(PremiumMetrics.cardPadding)
        .frame(maxWidth: .infinity, minHeight: PremiumMetrics.secondaryCardMinHeight, alignment: .top)
        .equalHeight()
        .background { PremiumCardBackground(accentColor: PremiumColors.teal, isHovered: isHovered) }
        .scaleEffect(isHovered ? 1.006 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
    }

    private func formatRate(_ bytesPerSec: Int64) -> String {
        if bytesPerSec >= 1024 * 1024 * 1024 {
            return String(format: "%.1f GB/s", Double(bytesPerSec) / (1024 * 1024 * 1024))
        } else if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1f MB/s", Double(bytesPerSec) / (1024 * 1024))
        } else if bytesPerSec >= 1024 {
            return String(format: "%.1f KB/s", Double(bytesPerSec) / 1024)
        }
        return String(format: "%d B/s", bytesPerSec)
    }

    private func formatTotal(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 100 {
            return String(format: "Total: %.0f GB", gb)
        } else if gb >= 10 {
            return String(format: "Total: %.1f GB", gb)
        } else if gb >= 1 {
            return String(format: "Total: %.2f GB", gb)
        }
        return String(format: "Total: %.0f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Premium System Info Card

struct PremiumSystemInfoCard: View {
    let systemInfo: SystemInfoPayload

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Clickable header
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isExpanded.toggle() } }) {
                HStack(spacing: PremiumMetrics.innerSpacing) {
                    HStack(spacing: PremiumMetrics.tightSpacing) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: PremiumMetrics.iconSizeSmall, weight: .semibold))
                            .foregroundColor(PremiumColors.violet)

                        Text("SYSTEM INFO")
                            .font(PremiumTypography.sectionHeader)
                            .foregroundColor(PremiumColors.textMuted)
                            .textCase(.uppercase)
                            .tracking(1.2)
                    }

                    Spacer()

                    // Quick summary when collapsed
                    if !isExpanded {
                        HStack(spacing: 12) {
                            // Java badge
                            HStack(spacing: 4) {
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 9))
                                Text("Java \(systemInfo.javaVersion)")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(PremiumColors.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.06)))

                            // OS badge
                            HStack(spacing: 4) {
                                Image(systemName: osIcon)
                                    .font(.system(size: 9))
                                Text(systemInfo.osName)
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(PremiumColors.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.06)))

                            // Server version badge
                            Text(systemInfo.minecraftVersion)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(PremiumColors.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PremiumColors.textMuted)
                }
                .padding(PremiumMetrics.cardPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable details
            if isExpanded {
                Divider()
                    .background(Color.white.opacity(0.08))

                VStack(spacing: PremiumMetrics.innerSpacing) {
                    // Hardware section
                    InfoSection(title: "Hardware") {
                        InfoRow(icon: "cpu", label: "Processor", value: systemInfo.cpuModel)
                        InfoRow(icon: "square.grid.3x3", label: "Cores", value: "\(systemInfo.cpuPhysicalCores) physical / \(systemInfo.cpuCores) logical")
                        InfoRow(icon: "memorychip", label: "System RAM", value: formatMemory(systemInfo.totalMemoryMB))
                    }

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // Software section
                    InfoSection(title: "Software") {
                        InfoRow(icon: "cup.and.saucer.fill", label: "Java Version", value: "\(systemInfo.javaVersion) (\(systemInfo.javaVendor))")
                        InfoRow(icon: "terminal", label: "JVM", value: systemInfo.jvmName)
                        InfoRow(icon: "server.rack", label: "Server", value: systemInfo.serverVersion)
                        InfoRow(icon: "gamecontroller", label: "Minecraft", value: systemInfo.minecraftVersion)
                    }

                    Divider()
                        .background(Color.white.opacity(0.06))

                    // OS section
                    InfoSection(title: "Operating System") {
                        InfoRow(icon: osIcon, label: "OS", value: "\(systemInfo.osName) \(systemInfo.osVersion)")
                        InfoRow(icon: "cpu", label: "Architecture", value: systemInfo.osArch)
                        if !systemInfo.networkInterfaces.isEmpty {
                            InfoRow(icon: "network", label: "Interfaces", value: systemInfo.networkInterfaces.joined(separator: ", "))
                        }
                    }
                }
                .padding(PremiumMetrics.cardPadding)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background { PremiumCardBackground(accentColor: PremiumColors.violet, isHovered: isHovered) }
        .scaleEffect(isHovered ? 1.004 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
    }

    private var osIcon: String {
        let os = systemInfo.osName.lowercased()
        if os.contains("linux") { return "terminal.fill" }
        if os.contains("mac") || os.contains("darwin") { return "apple.logo" }
        if os.contains("windows") { return "pc" }
        return "desktopcomputer"
    }

    private func formatMemory(_ mb: Int64) -> String {
        let gb = Double(mb) / 1024.0
        if gb >= 10 {
            return String(format: "%.0f GB", gb)
        }
        return String(format: "%.1f GB", gb)
    }
}

struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: PremiumMetrics.tightSpacing) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(PremiumColors.textSubtle)
                .textCase(.uppercase)
                .tracking(1)
                .padding(.bottom, 2)

            content
        }
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: PremiumMetrics.tightSpacing) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(PremiumColors.textSubtle)
                .frame(width: 16)

            Text(label)
                .font(PremiumTypography.label)
                .foregroundColor(PremiumColors.textMuted)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(PremiumColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
    }
}

// MARK: - Premium Player Indicator

struct PremiumPlayerIndicator: View {
    let playerCount: Int
    let maxPlayers: Int
    let players: [PlayersUpdatePayload.PlayerInfo]
    let sparklineData: [Double]

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            let hasPlayers = !players.isEmpty
            let isWaitingForPlayers = playerCount > 0 && !hasPlayers

            // Clickable header
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isExpanded.toggle() } }) {
                HStack(spacing: PremiumMetrics.cardSpacing) {
                    // Player icon with animated ring
                    ZStack {
                        Circle()
                            .fill(playerCount > 0 ? PremiumColors.sky.opacity(0.15) : Color.white.opacity(0.06))
                            .frame(width: 48, height: 48)

                        if playerCount > 0 {
                            Circle()
                                .stroke(PremiumColors.sky.opacity(0.3), lineWidth: 2)
                                .frame(width: 48, height: 48)
                        }

                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(playerCount > 0 ? PremiumColors.sky : PremiumColors.textSubtle)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("ONLINE PLAYERS")
                            .font(PremiumTypography.sectionHeader)
                            .foregroundColor(PremiumColors.textMuted)
                            .textCase(.uppercase)
                            .tracking(1.2)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(playerCount)")
                                .font(PremiumTypography.mediumValue)
                                .foregroundColor(PremiumColors.textPrimary)

                            Text("/ \(maxPlayers)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(PremiumColors.textSubtle)

                            // Capacity indicator
                            if maxPlayers > 0 {
                                let capacity = Double(playerCount) / Double(maxPlayers)
                                Text(String(format: "%.0f%%", capacity * 100))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(capacity > 0.8 ? PremiumColors.amber : PremiumColors.textMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.white.opacity(0.06))
                                    }
                            }
                        }
                    }

                    Spacer()

                    // Mini sparkline
                    if !sparklineData.isEmpty {
                        SparklineView(data: sparklineData, color: PremiumColors.sky, maxValue: Double(maxPlayers))
                            .frame(width: 80, height: 28)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PremiumColors.textMuted)
                }
                .padding(PremiumMetrics.cardPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable player grid
            if isExpanded && hasPlayers {
                Divider()
                    .background(Color.white.opacity(0.08))

                PlayerGridView(players: players)
                    .padding(PremiumMetrics.cardPadding)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if isExpanded && isWaitingForPlayers {
                Divider()
                    .background(Color.white.opacity(0.08))

                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: PremiumColors.sky))
                        Text("Loading player list…")
                            .font(PremiumTypography.caption)
                            .foregroundColor(PremiumColors.textMuted)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .transition(.opacity)
            } else if isExpanded && !hasPlayers {
                Divider()
                    .background(Color.white.opacity(0.08))

                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 24))
                            .foregroundColor(PremiumColors.textSubtle)
                        Text("No players online")
                            .font(PremiumTypography.caption)
                            .foregroundColor(PremiumColors.textMuted)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .background { PremiumCardBackground(accentColor: PremiumColors.sky, isHovered: isHovered) }
        .scaleEffect(isHovered ? 1.004 : 1.0)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)
        .onHover { isHovered = $0 }
        .onAppear { appeared = true }
    }
}

// MARK: - Premium Sparkline Components

struct PremiumDualSparkline: View {
    let primaryData: [Double]
    let secondaryData: [Double]
    let primaryColor: Color
    let secondaryColor: Color
    let primaryMax: Double
    let secondaryMax: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background grid lines
                VStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 1)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 1)
                    Spacer()
                }

                // Secondary line (MSPT) - rendered first (behind)
                if secondaryData.count > 1 {
                    Path { path in
                        for (index, value) in secondaryData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(secondaryData.count - 1)
                            let normalizedValue = min(value / secondaryMax, 1.0)
                            let y = geo.size.height * (1 - CGFloat(normalizedValue))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(secondaryColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }

                // Primary line (TPS) - rendered second (in front)
                if primaryData.count > 1 {
                    // Area fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (index, value) in primaryData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(primaryData.count - 1)
                            let normalizedValue = min(value / primaryMax, 1.0)
                            let y = geo.size.height * (1 - CGFloat(normalizedValue))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [primaryColor.opacity(0.2), primaryColor.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line
                    Path { path in
                        for (index, value) in primaryData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(primaryData.count - 1)
                            let normalizedValue = min(value / primaryMax, 1.0)
                            let y = geo.size.height * (1 - CGFloat(normalizedValue))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [primaryColor.opacity(0.6), primaryColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // Current value dot
                    if let lastValue = primaryData.last {
                        let x = geo.size.width
                        let normalizedValue = min(lastValue / primaryMax, 1.0)
                        let y = geo.size.height * (1 - CGFloat(normalizedValue))
                        Circle()
                            .fill(primaryColor)
                            .frame(width: 6, height: 6)
                            .position(x: x, y: y)
                            .shadow(color: primaryColor.opacity(0.5), radius: 4, x: 0, y: 0)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
        )
    }
}

struct PremiumNetworkSparkline: View {
    let rxData: [Double]
    let txData: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(
                rxData.max() ?? 1,
                txData.max() ?? 1,
                1
            )

            ZStack {
                // RX area fill
                if rxData.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for (index, value) in rxData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(rxData.count - 1)
                            let y = geo.size.height * (1 - CGFloat(value / maxVal))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(PremiumColors.emerald.opacity(0.15))

                    Path { path in
                        for (index, value) in rxData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(rxData.count - 1)
                            let y = geo.size.height * (1 - CGFloat(value / maxVal))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(PremiumColors.emerald.opacity(0.7), lineWidth: 1.5)
                }

                // TX line
                if txData.count > 1 {
                    Path { path in
                        for (index, value) in txData.enumerated() {
                            let x = geo.size.width * CGFloat(index) / CGFloat(txData.count - 1)
                            let y = geo.size.height * (1 - CGFloat(value / maxVal))
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(PremiumColors.sky.opacity(0.7), lineWidth: 1.5)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
        )
    }
}
