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
    /// Called when user scrolls - return true to consume the event (for remote scrollback)
    var onScrollWheel: ((CGFloat) -> Bool)?
    var size: CGSize  // Explicit size from GeometryReader

    // Reference to allow external data feeding
    @Binding var terminalRef: SwiftTerminalController?

    func makeNSView(context: Context) -> NSView {
        // Create a container view that will host the terminal
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let terminal = TerminalView(frame: container.bounds)
        terminal.terminalDelegate = context.coordinator
        terminal.autoresizingMask = [.width, .height]

        // Configure terminal appearance
        configureTerminal(terminal)

        container.addSubview(terminal)

        // Store terminal reference for coordinator
        context.coordinator.terminalView = terminal
        context.coordinator.installScrollMonitor()

        // Store reference for external data feeding
        DispatchQueue.main.async {
            self.terminalRef = SwiftTerminalController(terminalView: terminal)
        }

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update callbacks
        context.coordinator.onSendData = onSendData
        context.coordinator.onResize = onResize
        context.coordinator.onScrollWheel = onScrollWheel

        // Get the terminal view from container
        guard let terminal = nsView.subviews.first as? TerminalView else { return }
        context.coordinator.terminalView = terminal

        // Update frame when size changes
        if nsView.frame.size != size && size.width > 0 && size.height > 0 {
            nsView.frame = NSRect(origin: .zero, size: size)
            terminal.frame = nsView.bounds
            terminal.needsDisplay = true
        }
    }

    // Tell SwiftUI to use the proposed size
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        // Return the proposed size so the view fills available space
        return CGSize(
            width: proposal.width ?? size.width,
            height: proposal.height ?? size.height
        )
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

        // Increase scrollback buffer significantly (default is 500)
        // This enables smooth native scrolling through terminal history
        // Note: This only affects future buffer allocations, existing content is preserved
        terminal.getTerminal().options.scrollback = 10000
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, TerminalViewDelegate {
        var parent: SwiftTerminalView
        var onSendData: ((Data) -> Void)?
        var onResize: ((Int, Int) -> Void)?
        var onScrollWheel: ((CGFloat) -> Bool)?

        weak var terminalView: TerminalView?
        private var scrollMonitor: Any?

        init(_ parent: SwiftTerminalView) {
            self.parent = parent
            self.onSendData = parent.onSendData
            self.onResize = parent.onResize
            self.onScrollWheel = parent.onScrollWheel
        }

        deinit {
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        /// Install scroll wheel monitor to intercept scroll events for remote scrollback
        func installScrollMonitor() {
            guard scrollMonitor == nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let terminalView = self.terminalView,
                      let window = terminalView.window,
                      event.window === window else {
                    return event
                }

                // Only intercept if cursor is over terminal
                let point = terminalView.convert(event.locationInWindow, from: nil)
                guard terminalView.bounds.contains(point) else { return event }

                // Get scroll delta
                let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 3

                // Let handler decide whether to consume the event
                if let handler = self.onScrollWheel, handler(deltaY) {
                    return nil  // Consumed - don't pass to SwiftTerm
                }
                return event  // Pass through to SwiftTerm's native scrollback
            }
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
        GeometryReader { geometry in
            SwiftTerminalView(
                isConnected: $isConnected,
                onSendData: { data in
                    handleSendData(data)
                },
                onResize: { cols, rows in
                    handleResize(cols: cols, rows: rows)
                },
                onScrollWheel: { deltaY in
                    handleScrollWheel(deltaY: deltaY)
                },
                size: geometry.size,
                terminalRef: $terminalController
            )
        }
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
            if let controller = terminalController, !hasRegisteredCallback {
                hasRegisteredCallback = true
                registerPTYCallback()
                let dims = controller.dimensions
                handleResize(cols: dims.cols, rows: dims.rows)
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
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.resizePTY(for: server, cols: cols, rows: rows)
        }
    }

    // MARK: - Scroll Handling

    // Accumulated scroll delta for smooth scrolling
    @State private var scrollAccumulator: CGFloat = 0
    @State private var isInCopyMode = false
    @State private var lastScrollTime: Date = .distantPast

    private func handleScrollWheel(deltaY: CGFloat) -> Bool {
        guard let server = serverManager.selectedServer else { return false }

        // Only intercept for tmux/screen sessions (they use alternate screen with no scrollback)
        switch server.consoleMode {
        case .ptyTmux, .ptyScreen:
            break
        default:
            // Let SwiftTerm handle native scrollback for other modes
            return false
        }

        // Throttle: accumulate delta and send commands periodically
        scrollAccumulator += deltaY

        // Need at least ~3 units of scroll to trigger a line
        let threshold: CGFloat = 3.0
        guard abs(scrollAccumulator) >= threshold else { return true }

        let lines = Int(scrollAccumulator / threshold)
        scrollAccumulator = scrollAccumulator.truncatingRemainder(dividingBy: threshold)

        guard lines != 0 else { return true }

        Task {
            // Enter copy mode if not already (tmux: Ctrl+B [, screen: Ctrl+A Esc)
            let now = Date()
            let timeSinceLastScroll = now.timeIntervalSince(lastScrollTime)
            await MainActor.run { lastScrollTime = now }

            // Re-enter copy mode if it's been a while (copy mode may have exited)
            if timeSinceLastScroll > 2.0 || !isInCopyMode {
                await MainActor.run { isInCopyMode = true }
                if server.consoleMode == .ptyTmux {
                    await serverManager.sendPTYRaw("\u{02}[", to: server)  // Ctrl+B [
                } else {
                    await serverManager.sendPTYRaw("\u{01}\u{1B}", to: server)  // Ctrl+A Esc
                }
                // Small delay to let copy mode activate
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            }

            // Send arrow keys for smooth line-by-line scrolling
            let key: SpecialKey = lines > 0 ? .up : .down
            let count = abs(lines)
            for _ in 0..<min(count, 10) {  // Cap at 10 lines per scroll event
                await serverManager.sendPTYKey(key, to: server)
            }
        }

        return true  // Consume the event
    }
}

#Preview {
    SwiftTermConsoleView()
        .environmentObject(ServerManager())
        .frame(width: 800, height: 500)
}
