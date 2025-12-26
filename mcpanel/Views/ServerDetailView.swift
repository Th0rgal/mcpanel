//
//  ServerDetailView.swift
//  MCPanel
//
//  Main detail view showing server console, plugins, and files
//

import SwiftUI

struct ServerDetailView: View {
    @EnvironmentObject var serverManager: ServerManager

    var body: some View {
        if let server = serverManager.selectedServer {
            // Tab content with optional floating controls
            tabContent(server)
        } else {
            // Empty state with titlebar spacer
            VStack(spacing: 0) {
                Spacer().frame(height: 52)
                emptyState
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(_ server: Server) -> some View {
        switch serverManager.selectedTab {
        case .console:
            // Console view extends to top with fade effect
            ZStack(alignment: .topTrailing) {
                ConsoleView()
                    .environmentObject(serverManager)

                // Top fade gradient overlay
                VStack {
                    LinearGradient(
                        colors: [
                            Color(hex: "161618"),
                            Color(hex: "161618").opacity(0.8),
                            Color(hex: "161618").opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .allowsHitTesting(false)

                    Spacer()
                }

                // Floating server controls
                floatingServerControls(server)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        case .plugins:
            PluginsView()
                .environmentObject(serverManager)
                .padding(.top, 12)
        case .files:
            FileBrowserView()
                .environmentObject(serverManager)
                .padding(.top, 12)
        case .properties:
            ServerPropertiesView(server: server)
                .environmentObject(serverManager)
                .padding(.top, 12)
        case .settings:
            ServerSettingsView(server: server)
                .environmentObject(serverManager)
                .padding(.top, 12)
        }
    }

    // MARK: - Floating Server Controls

    private func floatingServerControls(_ server: Server) -> some View {
        HStack(spacing: 8) {
            // Status badge
            GlassStatusBadge(status: server.status)

            // Server controls
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
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 8)
            }

            // Refresh button
            GlassIconButton(icon: "arrow.triangle.2.circlepath") {
                Task { await serverManager.refreshServerStatus(server) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 8) {
                Text("No Server Selected")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text("Select a server from the sidebar or add a new one.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.5))
            }

            GlassButton(
                title: "Add Server",
                icon: "plus",
                style: .primary
            ) {
                NotificationCenter.default.post(name: .addServer, object: nil)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Glass Status Badge

struct GlassStatusBadge: View {
    let status: ServerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: status.color))
                .frame(width: 6, height: 6)
                .shadow(color: Color(hex: status.color).opacity(0.6), radius: 4)

            Text(status.rawValue)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(Color(hex: status.color).opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    enum Style {
        case primary
        case secondary
        case destructive

        var backgroundColor: Color {
            switch self {
            case .primary: return .green
            case .secondary: return .white
            case .destructive: return .red
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .white
            case .destructive: return .white
            }
        }
    }

    let title: String
    let icon: String
    let style: Style
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(style.foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Group {
                    if style == .secondary {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(style.backgroundColor.opacity(isHovered ? 0.9 : 0.8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(style.backgroundColor.opacity(0.5), lineWidth: 1)
                            }
                            .shadow(color: style.backgroundColor.opacity(0.3), radius: isHovered ? 8 : 4, y: 2)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Glass Icon Button

struct GlassIconButton: View {
    let icon: String
    var tint: Color? = nil
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tint ?? .white.opacity(0.8))
                .frame(width: 32, height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke((tint ?? Color.white).opacity(0.15), lineWidth: 1)
                        }
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Server Settings View

struct ServerSettingsView: View {
    @EnvironmentObject var serverManager: ServerManager
    let server: Server

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var sshPort: String = ""
    @State private var username: String = ""
    @State private var identityFile: String = ""
    @State private var serverPath: String = ""
    @State private var systemdUnit: String = ""
    @State private var screenSession: String = ""
    @State private var tmuxSession: String = ""
    @State private var consoleMode: ConsoleMode = .logTail

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Connection settings
                SettingsSection(title: "Connection") {
                    SettingsField(label: "Server Name", text: $name)
                    SettingsField(label: "Host", text: $host)
                    SettingsField(label: "SSH Port", text: $sshPort)
                    SettingsField(label: "Username", text: $username)
                    SettingsField(label: "SSH Key Path", text: $identityFile)
                }

                // Server settings
                SettingsSection(title: "Server") {
                    SettingsField(label: "Server Path", text: $serverPath)
                    SettingsField(label: "Systemd Unit", text: $systemdUnit)
                }

                // Console settings
                SettingsSection(title: "Console") {
                    // Console mode picker
                    HStack {
                        Text("Console Mode")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 120, alignment: .leading)

                        Picker("", selection: $consoleMode) {
                            ForEach(ConsoleMode.allCases) { mode in
                                HStack {
                                    Image(systemName: mode.icon)
                                    Text(mode.rawValue)
                                }
                                .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Mode description
                    Text(consoleMode.description)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.leading, 120)

                    // Session name fields (shown based on mode)
                    if consoleMode == .ptyScreen {
                        SettingsField(label: "Screen Session", text: $screenSession, placeholder: "e.g., minecraft")
                    } else if consoleMode == .ptyTmux {
                        SettingsField(label: "Tmux Session", text: $tmuxSession, placeholder: "e.g., mc-server")
                    }
                }

                // Save button
                HStack {
                    Spacer()

                    Button("Save Changes") {
                        var updated = server
                        updated.name = name
                        updated.host = host
                        updated.sshPort = Int(sshPort) ?? 22
                        updated.sshUsername = username
                        updated.identityFilePath = identityFile.isEmpty ? nil : identityFile
                        updated.serverPath = serverPath
                        updated.systemdUnit = systemdUnit.isEmpty ? nil : systemdUnit
                        updated.screenSession = screenSession.isEmpty ? nil : screenSession
                        updated.tmuxSession = tmuxSession.isEmpty ? nil : tmuxSession
                        updated.consoleMode = consoleMode

                        Task {
                            await serverManager.updateServer(updated)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .onAppear {
            name = server.name
            host = server.host
            sshPort = String(server.sshPort)
            username = server.sshUsername
            identityFile = server.identityFilePath ?? ""
            serverPath = server.serverPath
            systemdUnit = server.systemdUnit ?? ""
            screenSession = server.screenSession ?? ""
            tmuxSession = server.tmuxSession ?? ""
            consoleMode = server.consoleMode
        }
    }
}

// MARK: - Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 12) {
                content
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
    }
}

struct SettingsField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 120, alignment: .leading)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        }
                }
        }
    }
}
