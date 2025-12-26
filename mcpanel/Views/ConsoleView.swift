//
//  ConsoleView.swift
//  MCPanel
//
//  Live server console with command input
//

import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var commandText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Console output
            consoleOutput

            // Command input
            commandInput
        }
        .onAppear {
            // Load console when view appears
            if let server = serverManager.selectedServer {
                Task {
                    // Detect available sessions
                    await serverManager.detectPTYSessions(for: server)

                    // Connect based on console mode
                    if server.consoleMode == .logTail {
                        await serverManager.loadConsole(for: server)
                    } else {
                        await serverManager.connectPTY(for: server)
                    }
                }
            }
        }
        .onDisappear {
            // Disconnect PTY when leaving
            if let server = serverManager.selectedServer {
                Task {
                    await serverManager.disconnectPTY(for: server)
                }
            }
        }
    }

    // MARK: - Console Output

    private var consoleOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // Top spacer for fade effect area
                    Spacer().frame(height: 36)

                    if serverManager.selectedServerConsole.isEmpty {
                        // Empty state
                        VStack(spacing: 12) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.3))
                            Text("No console output")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))
                            Text("Click refresh to load logs")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        ForEach(serverManager.selectedServerConsole) { message in
                            ConsoleLineView(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(Color.clear)
            .onChange(of: serverManager.selectedServerConsole.count) { _, _ in
                // Auto-scroll to bottom
                if let last = serverManager.selectedServerConsole.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Command Input

    private var commandInput: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.custom("Menlo", size: 12))
                .foregroundStyle(Color(hex: "22C55E"))

            TextField("Enter command...", text: $commandText)
                .font(.custom("Menlo", size: 12))
                .textFieldStyle(.plain)
                .onSubmit {
                    sendCommand()
                }

            Button {
                sendCommand()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .disabled(commandText.isEmpty)
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
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func sendCommand() {
        guard !commandText.isEmpty, let server = serverManager.selectedServer else { return }

        Task {
            await serverManager.sendCommand(commandText, to: server)
            commandText = ""
        }
    }
}

// MARK: - Console Line View

struct ConsoleLineView: View {
    let message: ConsoleMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // For PTY raw output, show minimal UI
            if message.rawANSI {
                // Raw PTY output - just parse ANSI and display
                Text(coloredContent)
                    .font(.custom("Menlo", size: 12))
                    .textSelection(.enabled)
            } else {
                // Standard log format with timestamp and level
                // Timestamp
                Text(message.formattedTimestamp)
                    .font(.custom("Menlo", size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 60, alignment: .leading)

                // Level indicator
                Circle()
                    .fill(message.level.dotColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                // Source (if plugin)
                if let source = message.source {
                    Text("[\(source)]")
                        .font(.custom("Menlo-Bold", size: 11))
                        .foregroundColor(pluginColor(for: source))
                }

                // Content with rich color support
                Text(coloredContent)
                    .font(.custom("Menlo", size: 12))
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    // Parse content and apply color codes (ANSI or Minecraft)
    private var coloredContent: AttributedString {
        if message.rawANSI {
            // Use ANSI parser directly for PTY output
            return ANSIParser.parse(message.content)
        } else {
            // Use the Minecraft color parser for log output
            return MinecraftColorParser.parse(message.content, defaultColor: message.level.textColor)
        }
    }

    // Different colors for different plugin sources
    private func pluginColor(for source: String) -> Color {
        let hash = abs(source.hashValue)
        let colors: [Color] = [
            Color(hex: "55FF55"),  // Green
            Color(hex: "55FFFF"),  // Cyan
            Color(hex: "FF55FF"),  // Magenta
            Color(hex: "FFFF55"),  // Yellow
            Color(hex: "5555FF"),  // Blue
            Color(hex: "FF5555"),  // Red
            Color(hex: "FFAA00"),  // Gold
            Color(hex: "AA00AA"),  // Purple
        ]
        return colors[hash % colors.count]
    }
}

#Preview {
    ConsoleView()
        .environmentObject(ServerManager())
        .frame(width: 800, height: 500)
        .background(Color(hex: "161618"))
}
