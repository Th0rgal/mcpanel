//
//  ConsoleView.swift
//  MCPanel
//
//  Live server console with command input
//

import SwiftUI
import AppKit

struct ConsoleView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var commandText = ""
    @FocusState private var isCommandFieldFocused: Bool

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
                        await serverManager.acquirePTY(for: server, consumer: .console)
                    }
                }
            }
        }
        .onDisappear {
            // Disconnect PTY when leaving
            if let server = serverManager.selectedServer {
                serverManager.releasePTY(for: server, consumer: .console)
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

            TabInterceptingTextField(
                text: $commandText,
                placeholder: "Enter command...",
                onSubmit: { sendCommand() },
                onTab: { handleTabCompletion() },
                onTextChange: { oldText, newText in
                    handleTextChange(from: oldText, to: newText)
                }
            )
            .font(.custom("Menlo", size: 12))

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
            // The text is already in the PTY buffer (synced via handleTextChange)
            // Just send Enter to execute the command
            if serverManager.isPTYConnected(for: server) {
                await serverManager.sendPTYRaw("\n", to: server)
            } else {
                // Fallback for non-PTY mode
                await serverManager.sendCommand(commandText, to: server)
            }
            commandText = ""
        }
    }

    private func handleTabCompletion() {
        guard let server = serverManager.selectedServer else { return }

        // Send just Tab - the PTY should already have our text synced
        Task {
            await serverManager.sendPTYRaw("\t", to: server)
        }
    }

    private func handleTextChange(from oldText: String, to newText: String) {
        guard let server = serverManager.selectedServer,
              serverManager.isPTYConnected(for: server) else { return }

        Task {
            // Calculate the difference and send appropriate keystrokes
            if newText.count > oldText.count && newText.hasPrefix(oldText) {
                // Characters were added at the end
                let addedChars = String(newText.dropFirst(oldText.count))
                await serverManager.sendPTYRaw(addedChars, to: server)
            } else if newText.count < oldText.count && oldText.hasPrefix(newText) {
                // Characters were deleted from the end (backspace)
                let deleteCount = oldText.count - newText.count
                let backspaces = String(repeating: "\u{7F}", count: deleteCount)  // DEL character
                await serverManager.sendPTYRaw(backspaces, to: server)
            } else {
                // Text changed in a more complex way (paste, cut, etc.)
                // Clear the line and resend the full text
                let clearCount = oldText.count
                if clearCount > 0 {
                    let backspaces = String(repeating: "\u{7F}", count: clearCount)
                    await serverManager.sendPTYRaw(backspaces, to: server)
                }
                if !newText.isEmpty {
                    await serverManager.sendPTYRaw(newText, to: server)
                }
            }
        }
    }
}

// MARK: - Tab Intercepting TextField

/// A TextField wrapper that intercepts Tab key presses and syncs keystrokes to PTY
struct TabInterceptingTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onTab: () -> Void
    var onTextChange: ((String, String) -> Void)?  // (oldText, newText) for syncing to PTY

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont(name: "Menlo", size: 12)
        textField.textColor = .white
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        // Update callbacks in coordinator
        context.coordinator.onTab = onTab
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onTextChange = onTextChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TabInterceptingTextField
        var onTab: (() -> Void)?
        var onSubmit: (() -> Void)?
        var onTextChange: ((String, String) -> Void)?
        var previousText: String = ""

        init(_ parent: TabInterceptingTextField) {
            self.parent = parent
            self.onTab = parent.onTab
            self.onSubmit = parent.onSubmit
            self.onTextChange = parent.onTextChange
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                let newText = textField.stringValue
                let oldText = previousText
                previousText = newText
                parent.text = newText

                // Notify about the change so we can sync to PTY
                onTextChange?(oldText, newText)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Intercept Tab key (insertTab selector)
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                onTab?()
                return true // We handled it, don't do default tab behavior
            }
            // Intercept Enter key
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            return false
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
            // PTY output can contain ANSI escapes or Minecraft/Adventure formatting; support both.
            return MinecraftColorParser.parse(message.content, defaultColor: message.level.textColor)
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
