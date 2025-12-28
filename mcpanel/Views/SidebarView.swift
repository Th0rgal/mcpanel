//
//  SidebarView.swift
//  MCPanel
//
//  Server list sidebar with liquid glass navigation
//

import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var serverManager: ServerManager

    private let contentInsetX: CGFloat = 12
    private let titlebarSpacerHeight: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Titlebar space (draggable area)
            WindowDragArea()
                .frame(height: titlebarSpacerHeight)

            // App header
            appHeader

            // Servers section
            serversSection

            Spacer()

            // Navigation tabs (when server is selected)
            if serverManager.selectedServer != nil {
                navigationTabs
            }

            // Add server button
            addServerButton
        }
        .padding(.top, 6)
    }

    // MARK: - App Header

    private var appHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "server.rack")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Text("MCPanel")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, contentInsetX + 4)
        .padding(.bottom, 16)
        .background(WindowDragArea())
    }

    // MARK: - Servers Section

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            SidebarSectionHeader(title: "Servers")

            ForEach(serverManager.servers) { server in
                ServerRow(
                    server: server,
                    isSelected: isServerSelected(server)
                ) {
                    serverManager.selectedSidebar = .server(server.id)
                    Task {
                        await serverManager.refreshServerStatus(server)
                        await serverManager.loadConsole(for: server)
                        await serverManager.loadPlugins(for: server)
                        await serverManager.loadFiles(for: server)
                    }
                }
                .contextMenu {
                    Button("Refresh Status") {
                        Task { await serverManager.refreshServerStatus(server) }
                    }

                    Divider()

                    if server.status == .online {
                        Button("Stop Server") {
                            Task { await serverManager.stopServer(server) }
                        }
                        Button("Restart Server") {
                            Task { await serverManager.restartServer(server) }
                        }
                    } else {
                        Button("Start Server") {
                            Task { await serverManager.startServer(server) }
                        }
                    }

                    Divider()

                    Button("Remove", role: .destructive) {
                        Task { await serverManager.removeServer(server) }
                    }
                }
            }
        }
        .padding(.horizontal, contentInsetX)
    }

    // MARK: - Navigation Tabs

    private var navigationTabs: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 4)
                .padding(.vertical, 12)

            ForEach(DetailTab.allCases) { tab in
                GlassTabButton(
                    tab: tab,
                    isSelected: serverManager.selectedTab == tab
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        serverManager.selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, contentInsetX)
        .padding(.bottom, 8)
    }

    // MARK: - Add Server Button

    private var addServerButton: some View {
        Button {
            NotificationCenter.default.post(name: .showAddServer, object: nil)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary.opacity(0.5))
                    .frame(width: 22)

                Text("Add Server")
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.5))

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, contentInsetX)
        .padding(.bottom, 18)
    }

    // MARK: - Helpers

    private func isServerSelected(_ server: Server) -> Bool {
        if case .server(let id) = serverManager.selectedSidebar {
            return id == server.id
        }
        return false
    }
}

// MARK: - Glass Tab Button

struct GlassTabButton: View {
    let tab: DetailTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .frame(width: 20)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    // Liquid glass effect
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .white.opacity(0.05), radius: 8, x: 0, y: 2)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Server Row

struct ServerRow: View {
    let server: Server
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Status indicator with glow effect for online
                ZStack {
                    if server.status == .online {
                        Circle()
                            .fill(Color(hex: server.status.color).opacity(0.3))
                            .frame(width: 14, height: 14)
                    }
                    Circle()
                        .fill(Color(hex: server.status.color))
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(server.host)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Server type icon
                Image(systemName: server.serverType.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        }
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.06))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sidebar Section Header

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(1.2)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }
}

// MARK: - Add Server Sheet

struct AddServerSheet: View {
    @EnvironmentObject var serverManager: ServerManager
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var host = ""
    @State private var sshPort = "22"
    @State private var username = "root"
    @State private var identityFile = "~/.ssh/id_rsa"
    @State private var serverPath = ""
    @State private var systemdUnit = ""
    @State private var serverType: ServerType = .paper

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Server")
                .font(.system(size: 16, weight: .semibold))

            Form {
                Section {
                    TextField("Server Name", text: $name)
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                    TextField("SSH Port", text: $sshPort)
                    TextField("Username", text: $username)
                    TextField("SSH Key Path", text: $identityFile)
                }

                Section {
                    TextField("Server Path", text: $serverPath)
                        .textContentType(.URL)
                    TextField("Systemd Unit", text: $systemdUnit)
                    Picker("Server Type", selection: $serverType) {
                        ForEach(ServerType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 350)

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Add") {
                    let server = Server(
                        name: name.isEmpty ? "Server" : name,
                        host: host,
                        sshPort: Int(sshPort) ?? 22,
                        sshUsername: username,
                        identityFilePath: identityFile.isEmpty ? nil : identityFile,
                        serverPath: serverPath,
                        systemdUnit: systemdUnit.isEmpty ? nil : systemdUnit,
                        serverType: serverType
                    )
                    Task {
                        await serverManager.addServer(server)
                        isPresented = false
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || serverPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
