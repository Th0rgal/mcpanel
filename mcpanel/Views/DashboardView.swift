//
//  DashboardView.swift
//  MCPanel
//
//  Real-time server performance dashboard with TPS, memory, players, and charts
//

import SwiftUI
import Charts
import Combine

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
                // Server header with status
                serverHeader

                // Show full dashboard if bridge has data
                if hasBridgeData, let _ = bridge {
                    // Bridge is available - show full dashboard
                    metricsGrid

                    performanceChart

                    playerSection
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
                await serverManager.acquirePTY(for: server, consumer: .dashboard)
            }
            // Request high-frequency updates when dashboard is visible
            serverManager.setDashboardActive(true, for: server.id)
        }
        .onDisappear {
            // Revert to low-frequency updates
            serverManager.setDashboardActive(false, for: server.id)
            serverManager.releasePTY(for: server, consumer: .dashboard)
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
        HStack(spacing: 16) {
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

                    if let bridge = serverManager.bridgeServices[server.id],
                       let status = bridge.serverStatus {
                        Text("Uptime: \(formatUptime(status.uptimeSeconds))")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
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

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        let bridge = serverManager.bridgeServices[server.id]
        let status = bridge?.serverStatus
        let history = bridge?.performanceHistory

        return VStack(spacing: 16) {
            // Primary metrics row
            HStack(spacing: 16) {
                // TPS Card - Most important metric
                PrimaryMetricCard(
                    title: "TPS",
                    value: status.map { String(format: "%.2f", $0.tps) } ?? "--",
                    maxValue: "20.00",
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    color: tpsColor(status?.tps),
                    sparklineData: history?.tpsHistory.suffix(60).map { $0.value } ?? [],
                    chartMaxValue: 20,
                    trend: calculateTrend(history?.tpsHistory.suffix(20).map { $0.value } ?? [])
                )

                // MSPT Card
                PrimaryMetricCard(
                    title: "MSPT",
                    value: status?.mspt.map { String(format: "%.1f", $0) } ?? "--",
                    maxValue: "50ms",
                    icon: "clock.badge",
                    color: msptColor(status?.mspt),
                    sparklineData: history?.msptHistory.suffix(60).map { $0.value } ?? [],
                    chartMaxValue: 100,
                    trend: calculateTrend(history?.msptHistory.suffix(20).map { $0.value } ?? [], inverted: true)
                )
            }

            // Secondary metrics row
            HStack(spacing: 16) {
                // Memory Card with precise values
                MemoryMetricCard(
                    usedMB: status?.usedMemoryMB ?? 0,
                    maxMB: status?.maxMemoryMB ?? 1,
                    color: memoryColor(status)
                )

                // Players Card
                PlayersMetricCard(
                    current: status?.playerCount ?? 0,
                    max: status?.maxPlayers ?? 0,
                    sparklineData: history?.playerCountHistory.suffix(60).map { $0.value } ?? []
                )

                // Uptime Card
                UptimeMetricCard(
                    uptimeSeconds: status?.uptimeSeconds ?? 0
                )
            }
        }
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
                    .frame(height: 200)
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
                .frame(height: 200)
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

// MARK: - Performance Chart View

struct PerformanceChartView: View {
    @ObservedObject var history: PerformanceHistory
    @State private var selectedTimeRange: TimeRange = .fiveMinutes

    enum TimeRange: String, CaseIterable {
        case oneMinute = "1m"
        case fiveMinutes = "5m"
        case fifteenMinutes = "15m"
        case thirtyMinutes = "30m"

        var sampleCount: Int {
            switch self {
            case .oneMinute: return 120      // 1 min at 500ms
            case .fiveMinutes: return 600    // 5 min at 500ms
            case .fifteenMinutes: return 1800
            case .thirtyMinutes: return 3600
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Time range selector
            HStack {
                Spacer()

                ForEach(TimeRange.allCases, id: \.self) { range in
                    Button(action: { selectedTimeRange = range }) {
                        Text(range.rawValue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(selectedTimeRange == range ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                if selectedTimeRange == range {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Chart
            let tpsData = Array(history.tpsHistory.suffix(selectedTimeRange.sampleCount))
            // Note: msptData could be added as a second line series in the future
            // let msptData = Array(history.msptHistory.suffix(selectedTimeRange.sampleCount))

            if !tpsData.isEmpty {
                Chart {
                    // TPS line
                    ForEach(Array(tpsData.enumerated()), id: \.element.id) { index, point in
                        LineMark(
                            x: .value("Time", index),
                            y: .value("TPS", point.value),
                            series: .value("Metric", "TPS")
                        )
                        .foregroundStyle(Color(hex: "22C55E"))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // Target TPS line at 20
                    RuleMark(y: .value("Target", 20))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
                .chartYScale(domain: 0...25)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let tps = value.as(Double.self) {
                                Text("\(Int(tps))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        AxisGridLine()
                            .foregroundStyle(Color.white.opacity(0.1))
                    }
                }
                .chartLegend(.hidden)
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

    var body: some View {
        HStack(spacing: 10) {
            // Player avatar (Crafatar)
            AsyncImage(url: URL(string: "https://crafatar.com/avatars/\(player.uuid)?size=32&overlay")) { image in
                image
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } placeholder: {
                Image(systemName: "person.fill")
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // World
                    Text(player.world)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)

                    // Ping indicator
                    HStack(spacing: 2) {
                        Circle()
                            .fill(pingColor(player.ping))
                            .frame(width: 6, height: 6)

                        Text("\(player.ping)ms")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func pingColor(_ ping: Int) -> Color {
        if ping < 100 { return Color(hex: "22C55E") }
        if ping < 200 { return Color(hex: "EAB308") }
        return Color(hex: "EF4444")
    }
}

// MARK: - Basic Info Card (for no-bridge state)

struct BasicInfoCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.15))
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))

                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
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

// MARK: - Uptime Metric Card

struct UptimeMetricCard: View {
    let uptimeSeconds: Int64

    @State private var isHovered = false

    private var days: Int64 { uptimeSeconds / 86400 }
    private var hours: Int64 { (uptimeSeconds % 86400) / 3600 }
    private var minutes: Int64 { (uptimeSeconds % 3600) / 60 }
    private var seconds: Int64 { uptimeSeconds % 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.purple)

                    Text("Uptime")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                Spacer()
            }
            .padding(.bottom, 10)

            // Time display
            if days > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(days)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("d")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Text("\(hours)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.leading, 4)
                    Text("h")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    Text("\(minutes)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.leading, 2)
                    Text("m")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.3))
                }
            } else if hours > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(hours)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("h")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Text("\(minutes)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.leading, 4)
                    Text("m")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(minutes)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("m")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Text("\(seconds)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.leading, 4)
                    Text("s")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()
                .frame(height: 24)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.purple.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
                }
        }
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
