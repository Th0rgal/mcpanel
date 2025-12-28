//
//  CommandDebugPanel.swift
//  MCPanel
//
//  Debug panel for command completion diagnostics
//

import SwiftUI

/// Debug panel that shows command completion state and allows testing
struct CommandDebugPanel: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var testPrefix: String = ""
    @State private var testResults: [String] = []
    @State private var isRefreshing = false
    @State private var showRawJSON = false
    @State private var rawJSONContent: String = ""

    private let logger = DebugLogger.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("Command Completion Debug")
                        .font(.headline)
                    Spacer()
                    Button("Refresh") {
                        Task { await refreshData() }
                    }
                    .disabled(isRefreshing)
                }

                Divider()

                // Server info
                if let server = serverManager.selectedServer {
                    serverInfoSection(server)
                } else {
                    Text("No server selected")
                        .foregroundColor(.secondary)
                }

                Divider()

                // Bridge status
                bridgeStatusSection

                Divider()

                // Command tree status
                commandTreeSection

                Divider()

                // Test autocomplete
                testSection

                Divider()

                // Log file info
                logFileSection
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            Task { await refreshData() }
        }
    }

    // MARK: - Sections

    private func serverInfoSection(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Text("Name:")
                    .foregroundColor(.secondary)
                Text(server.name)
            }

            HStack {
                Text("Host:")
                    .foregroundColor(.secondary)
                Text("\(server.sshUsername)@\(server.host):\(server.sshPort)")
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Server Path:")
                    .foregroundColor(.secondary)
                Text(server.serverPath)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("Plugins Path:")
                    .foregroundColor(.secondary)
                Text(server.effectivePluginsPath)
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private var bridgeStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bridge Status")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let server = serverManager.selectedServer {
                let bridge = serverManager.bridgeServices[server.id]
                let detected = bridge?.bridgeDetected ?? false

                HStack {
                    Circle()
                        .fill(detected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(detected ? "Detected" : "Not Detected")
                }

                if let bridge = bridge {
                    if let version = bridge.bridgeVersion {
                        HStack {
                            Text("Version:")
                                .foregroundColor(.secondary)
                            Text(version)
                        }
                    }

                    if let platform = bridge.platform {
                        HStack {
                            Text("Platform:")
                                .foregroundColor(.secondary)
                            Text(platform)
                        }
                    }

                    if !bridge.features.isEmpty {
                        HStack(alignment: .top) {
                            Text("Features:")
                                .foregroundColor(.secondary)
                            Text(bridge.features.sorted().joined(separator: ", "))
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            } else {
                Text("No server selected")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var commandTreeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Command Tree")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if let server = serverManager.selectedServer {
                    Button("Fetch Now") {
                        Task {
                            isRefreshing = true
                            let bridge = serverManager.bridgeService(for: server)
                            await bridge.fetchCommandTree()
                            isRefreshing = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if let server = serverManager.selectedServer {
                let tree = serverManager.commandTree[server.id]
                let bridge = serverManager.bridgeServices[server.id]

                HStack {
                    Text("Root Commands:")
                        .foregroundColor(.secondary)
                    Text("\(tree?.rootCommands.count ?? 0)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Bridge Tree Commands:")
                        .foregroundColor(.secondary)
                    Text("\(bridge?.commandTree?.commands.count ?? 0)")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("Update Count:")
                        .foregroundColor(.secondary)
                    Text("\(serverManager.commandTreeUpdateCount)")
                        .font(.system(.body, design: .monospaced))
                }

                // Sample commands
                if let tree = tree, !tree.rootCommands.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sample Commands (first 20):")
                            .foregroundColor(.secondary)

                        let sorted = tree.rootCommands.sorted()
                        let sample = sorted.prefix(20)
                        Text(sample.joined(separator: ", "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Show raw JSON button
                Button(showRawJSON ? "Hide Raw JSON" : "Show Raw JSON") {
                    if !showRawJSON {
                        loadRawJSON()
                    }
                    showRawJSON.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if showRawJSON && !rawJSONContent.isEmpty {
                    ScrollView(.horizontal) {
                        Text(rawJSONContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(4)
                }
            }
        }
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test Autocomplete")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                TextField("Type command prefix...", text: $testPrefix)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: testPrefix) { _, newValue in
                        performTest(newValue)
                    }

                Button("Test") {
                    performTest(testPrefix)
                }
                .buttonStyle(.bordered)
            }

            if !testResults.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Results (\(testResults.count)):")
                        .foregroundColor(.secondary)

                    ForEach(testResults.prefix(20), id: \.self) { result in
                        Text(result)
                            .font(.system(.body, design: .monospaced))
                    }

                    if testResults.count > 20 {
                        Text("... and \(testResults.count - 20) more")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } else if !testPrefix.isEmpty {
                Text("No results")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var logFileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Debug Logs")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Text("Log file:")
                    .foregroundColor(.secondary)
                Text(logger.logFilePath)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Open") {
                    NSWorkspace.shared.selectFile(logger.logFilePath, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Enable Verbose Logging") {
                logger.setVerbose(true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Actions

    private func refreshData() async {
        guard let server = serverManager.selectedServer else { return }
        isRefreshing = true

        // Trigger command tree fetch
        let bridge = serverManager.bridgeService(for: server)
        await bridge.fetchCommandTree()

        isRefreshing = false
    }

    private func performTest(_ prefix: String) {
        guard let server = serverManager.selectedServer else {
            testResults = []
            return
        }

        // Use the bridge service for completions
        if let bridge = serverManager.bridgeServices[server.id] {
            let completions = bridge.getCompletions(buffer: prefix)
            testResults = completions.map { $0.text }
        } else {
            // Fall back to ServerManager's command tree
            let tree = serverManager.commandTree[server.id]
            let lowercasePrefix = prefix.lowercased()
            testResults = tree?.rootCommands
                .filter { $0.lowercased().hasPrefix(lowercasePrefix) }
                .sorted() ?? []
        }
    }

    private func loadRawJSON() {
        guard let server = serverManager.selectedServer else { return }
        if let bridge = serverManager.bridgeServices[server.id],
           let tree = bridge.commandTree {
            if let data = try? JSONEncoder().encode(tree),
               let json = String(data: data, encoding: .utf8) {
                // Pretty print
                if let jsonData = try? JSONSerialization.jsonObject(with: data),
                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    rawJSONContent = String(prettyString.prefix(10000))
                } else {
                    rawJSONContent = String(json.prefix(5000))
                }
            }
        }
    }
}

// MARK: - Debug Menu Item

struct DebugMenuItem: View {
    @State private var showDebugPanel = false

    var body: some View {
        Button("Command Completion Debug...") {
            showDebugPanel = true
        }
        .keyboardShortcut("D", modifiers: [.command, .option])
        .sheet(isPresented: $showDebugPanel) {
            CommandDebugPanel()
                .frame(minWidth: 500, minHeight: 600)
        }
    }
}

#Preview {
    CommandDebugPanel()
        .environmentObject(ServerManager())
        .frame(width: 500, height: 700)
}
