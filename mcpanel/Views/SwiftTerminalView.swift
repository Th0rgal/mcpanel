//
//  SwiftTerminalView.swift
//  MCPanel
//
//  SwiftTerm-based terminal emulator for server console
//

import SwiftUI
import SwiftTerm
import AppKit

// MARK: - SwiftTerm NSView Wrapper

/// A SwiftUI wrapper around SwiftTerm's TerminalView for full terminal emulation
struct SwiftTerminalView: NSViewRepresentable {
    @Binding var isConnected: Bool
    var onSendData: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?  // cols, rows

    // Reference to allow external data feeding
    @Binding var terminalRef: SwiftTerminalController?

    func makeNSView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero)
        terminal.terminalDelegate = context.coordinator

        // Configure terminal appearance
        configureTerminal(terminal)

        // Store reference for external data feeding
        DispatchQueue.main.async {
            self.terminalRef = SwiftTerminalController(terminalView: terminal)
        }

        return terminal
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Update connection state visual feedback if needed
        context.coordinator.onSendData = onSendData
        context.coordinator.onResize = onResize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func configureTerminal(_ terminal: TerminalView) {
        // Set dark theme colors matching our app
        terminal.nativeForegroundColor = NSColor.white
        terminal.nativeBackgroundColor = NSColor(red: 0.086, green: 0.086, blue: 0.094, alpha: 1.0)  // #161618

        // Set cursor color
        terminal.caretColor = NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)  // Green like our prompt

        // Font configuration - use Menlo to match our existing console
        terminal.font = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Terminal options
        terminal.optionAsMetaKey = true
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, TerminalViewDelegate {
        var parent: SwiftTerminalView
        var onSendData: ((Data) -> Void)?
        var onResize: ((Int, Int) -> Void)?

        init(_ parent: SwiftTerminalView) {
            self.parent = parent
            self.onSendData = parent.onSendData
            self.onResize = parent.onResize
        }

        // Called when user types - send to PTY
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let dataToSend = Data(data)
            onSendData?(dataToSend)
        }

        // Called when terminal scrollback changes
        func scrolled(source: TerminalView, position: Double) {
            // Optional: handle scroll position changes
        }

        // Called when terminal title changes
        func setTerminalTitle(source: TerminalView, title: String) {
            // Optional: could update window title
        }

        // Called when terminal is resized
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize?(newCols, newRows)
        }

        // Called when terminal requests clipboard access
        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(string, forType: .string)
            }
        }

        // Called to request clipboard paste
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }

        // Bell sound
        func bell(source: TerminalView) {
            NSSound.beep()
        }

        // Selection changed
        func selectionChanged(source: TerminalView) {
            // Optional: handle selection changes
        }

        // Host lookup for hyperlinks
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            // Optional: track current directory
        }

        // Range changed callback
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
            // Optional: handle range changes for accessibility
        }
    }
}

// MARK: - Terminal Controller

/// Controller class to allow external code to feed data to the terminal
class SwiftTerminalController {
    private weak var terminalView: TerminalView?

    init(terminalView: TerminalView) {
        self.terminalView = terminalView
    }

    /// Feed data received from PTY into the terminal
    func feed(data: Data) {
        let byteArray = ArraySlice([UInt8](data))
        terminalView?.feed(byteArray: byteArray)
    }

    /// Feed a string into the terminal
    func feed(text: String) {
        if let data = text.data(using: .utf8) {
            feed(data: data)
        }
    }

    /// Get terminal dimensions
    var dimensions: (cols: Int, rows: Int) {
        guard let terminal = terminalView else { return (80, 24) }
        return (terminal.getTerminal().cols, terminal.getTerminal().rows)
    }

    /// Clear the terminal screen
    func clear() {
        // Send clear screen escape sequence
        feed(text: "\u{1B}[2J\u{1B}[H")
    }
}

// MARK: - Console View with SwiftTerm

struct SwiftTermConsoleView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var terminalController: SwiftTerminalController?
    @State private var isConnected = false
    @State private var hasRegisteredCallback = false

    var body: some View {
        SwiftTerminalView(
            isConnected: $isConnected,
            onSendData: { data in
                handleSendData(data)
            },
            onResize: { cols, rows in
                handleResize(cols: cols, rows: rows)
            },
            terminalRef: $terminalController
        )
        .onAppear {
            connectToServer()
        }
        .onDisappear {
            disconnectFromServer()
        }
        .onChange(of: serverManager.selectedServer?.id) { _, _ in
            // Reconnect when server changes
            hasRegisteredCallback = false
            disconnectFromServer()
            connectToServer()
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // Register callback when terminal controller becomes available
            if terminalController != nil && !hasRegisteredCallback {
                hasRegisteredCallback = true
                registerPTYCallback()
            }
        }
    }

    private func connectToServer() {
        guard let server = serverManager.selectedServer else { return }

        Task {
            // Detect available sessions
            await serverManager.detectPTYSessions(for: server)

            // Connect based on console mode
            if server.consoleMode == .logTail {
                await serverManager.loadConsole(for: server)
            } else {
                await serverManager.connectPTY(for: server)
            }

            await MainActor.run {
                isConnected = serverManager.isPTYConnected(for: server)
                // Register callback after connection
                registerPTYCallback()
            }
        }
    }

    private func disconnectFromServer() {
        guard let server = serverManager.selectedServer else { return }

        // Unregister callback
        serverManager.unregisterPTYOutputCallback(for: server)

        Task {
            await serverManager.disconnectPTY(for: server)
        }
    }

    private func registerPTYCallback() {
        guard let server = serverManager.selectedServer,
              let controller = terminalController else { return }

        // Register callback to receive raw PTY output
        serverManager.registerPTYOutputCallback(for: server) { output in
            // Feed raw PTY output directly to SwiftTerm
            controller.feed(text: output)
        }
    }

    private func handleSendData(_ data: Data) {
        guard let server = serverManager.selectedServer else { return }

        Task {
            if let text = String(data: data, encoding: .utf8) {
                await serverManager.sendPTYRaw(text, to: server)
            }
        }
    }

    private func handleResize(cols: Int, rows: Int) {
        // TODO: Send terminal resize to PTY if supported
        // This would require adding resize support to PTYService
    }
}

#Preview {
    SwiftTermConsoleView()
        .environmentObject(ServerManager())
        .frame(width: 800, height: 500)
}
