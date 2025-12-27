//
//  PluginsView.swift
//  MCPanel
//
//  Plugin management view with enable/disable toggle
//

import SwiftUI

struct PluginsView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var searchText = ""
    @State private var showDisabled = true

    var filteredPlugins: [Plugin] {
        var plugins = serverManager.selectedServerPlugins

        if !showDisabled {
            plugins = plugins.filter { $0.isEnabled }
        }

        if !searchText.isEmpty {
            plugins = plugins.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }

        return plugins
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            // Plugin list
            if filteredPlugins.isEmpty {
                emptyState
            } else {
                pluginList
            }
        }
        .onAppear {
            // Load plugins when view appears
            if let server = serverManager.selectedServer {
                Task {
                    await serverManager.loadPlugins(for: server)
                }
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Search plugins...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
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
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .frame(maxWidth: 300)

            Spacer()

            // Show disabled toggle
            Toggle("Show Disabled", isOn: $showDisabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            // Refresh button
            Button {
                refreshPlugins()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }

            // Upload button
            Button {
                // TODO: Implement file picker for plugin upload
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 12, weight: .medium))
                    Text("Upload")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - Plugin List

    private var pluginList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filteredPlugins) { plugin in
                    PluginRow(plugin: plugin) {
                        togglePlugin(plugin)
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Plugins Found")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)

            if searchText.isEmpty {
                Text("No plugins installed on this server.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            } else {
                Text("No plugins match your search.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            Button {
                refreshPlugins()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func refreshPlugins() {
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.loadPlugins(for: server)
        }
    }

    private func togglePlugin(_ plugin: Plugin) {
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.togglePlugin(plugin, for: server)
        }
    }
}

// MARK: - Plugin Row

struct PluginRow: View {
    let plugin: Plugin
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // Plugin icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: plugin.statusColor).opacity(0.2))

                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: plugin.statusColor))
            }
            .frame(width: 40, height: 40)

            // Plugin info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(plugin.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(plugin.isEnabled ? .primary : .secondary)
                        .strikethrough(!plugin.isEnabled, color: .secondary)

                    if let version = plugin.version {
                        Text("v\(version)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Capsule())
                    }
                }

                Text(plugin.fileName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // File size
            Text(plugin.formattedFileSize)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            // Enable/Disable toggle
            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
        }
        .onHover { isHovered = $0 }
    }
}

#Preview {
    PluginsView()
        .environmentObject(ServerManager())
        .frame(width: 800, height: 500)
        .background(Color(hex: "161618"))
}
