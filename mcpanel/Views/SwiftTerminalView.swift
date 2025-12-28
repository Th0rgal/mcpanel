//
//  SwiftTerminalView.swift
//  MCPanel
//
//  SwiftTerm-based terminal emulator for server console
//

import SwiftUI
import SwiftTerm
import AppKit

// MARK: - Terminal container (selection + event correctness)

/// SwiftTerm's `TerminalView` overrides some mouse handlers in a way that makes it hard to customize
/// selection/window-drag behavior in a SwiftUI hidden-titlebar window.
///
/// We wrap it in a container that:
/// - accepts first mouse (so selection works even if the window was inactive),
/// - opts out of window dragging,
/// - forwards mouse events to the embedded `TerminalView`.
final class MCPanelTerminalContainerView: NSView {
    let terminalView: TerminalView

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: frame)

        wantsLayer = true
        addSubview(terminalView)
        terminalView.frame = bounds
        terminalView.autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // Capture all mouse interactions and forward them to the underlying terminal view.
    // Returning `self` from hitTest ensures our acceptsFirstMouse/mouseDownCanMoveWindow take effect.
    override func hitTest(_ point: NSPoint) -> NSView? {
        // If SwiftTerm has interactive subviews (e.g., scroller), let them receive events directly.
        let terminalPoint = terminalView.convert(point, from: self)
        if let hit = terminalView.hitTest(terminalPoint), hit !== terminalView {
            return hit
        }
        // Otherwise, intercept at the container level so our mouse policies apply,
        // and forward events to the embedded terminal view.
        return self
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(terminalView)
        terminalView.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        terminalView.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        terminalView.mouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        terminalView.mouseMoved(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        terminalView.rightMouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        terminalView.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        terminalView.rightMouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        terminalView.scrollWheel(with: event)
    }
}

// MARK: - SwiftTerm NSView Wrapper

/// A SwiftUI wrapper around SwiftTerm's TerminalView for full terminal emulation
struct SwiftTerminalView: NSViewRepresentable {
    typealias NSViewType = MCPanelTerminalContainerView
    @Binding var isConnected: Bool
    var onSendData: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?  // cols, rows
    /// Called when user scrolls - return true to consume the event (for remote scrollback)
    var onScrollWheel: ((CGFloat) -> Bool)?
    var size: CGSize  // Explicit size from GeometryReader

    // Reference to allow external data feeding
    @Binding var terminalRef: SwiftTerminalController?

    func makeNSView(context: Context) -> MCPanelTerminalContainerView {
        // Create SwiftTerm terminal view
        let terminal = TerminalView(frame: NSRect(origin: .zero, size: size))
        terminal.terminalDelegate = context.coordinator

        // Configure terminal appearance
        configureTerminal(terminal)

        // Wrap in container to control mouse behavior (selection vs window drag)
        let container = MCPanelTerminalContainerView(
            frame: NSRect(origin: .zero, size: size),
            terminalView: terminal
        )

        // Store references for coordinator
        context.coordinator.containerView = container
        context.coordinator.terminalView = terminal
        context.coordinator.installScrollMonitor()

        // Store reference for external data feeding
        DispatchQueue.main.async {
            self.terminalRef = SwiftTerminalController(terminalView: terminal)
            // Make terminal first responder to capture keyboard input including Tab
            terminal.window?.makeFirstResponder(terminal)
        }

        return container
    }

    func updateNSView(_ container: MCPanelTerminalContainerView, context: Context) {
        // Update callbacks
        context.coordinator.onSendData = onSendData
        context.coordinator.onResize = onResize
        context.coordinator.onScrollWheel = onScrollWheel

        context.coordinator.containerView = container
        context.coordinator.terminalView = container.terminalView

        // Update frame when size changes
        if container.frame.size != size && size.width > 0 && size.height > 0 {
            container.frame = NSRect(origin: .zero, size: size)
            container.terminalView.frame = container.bounds
            container.needsDisplay = true
            container.terminalView.needsDisplay = true
        }
    }

    // Tell SwiftUI to use the proposed size
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TerminalView, context: Context) -> CGSize? {
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
        // Set transparent background to let app's dark theme show through
        terminal.nativeForegroundColor = NSColor.white
        terminal.nativeBackgroundColor = NSColor.clear

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
        weak var containerView: MCPanelTerminalContainerView?
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
                      let containerView = self.containerView,
                      let window = containerView.window,
                      event.window === window else {
                    return event
                }

                // Only intercept if cursor is over terminal
                let point = containerView.convert(event.locationInWindow, from: nil)
                guard containerView.bounds.contains(point) else { return event }

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
            // Debug: log what's being sent
            let bytes = Array(data)
            if bytes.contains(0x09) {
                print("[SwiftTerm] Sending TAB (0x09)")
            }
            print("[SwiftTerm] send: \(bytes.map { String(format: "0x%02X", $0) }.joined(separator: " "))")
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
            #if DEBUG
            // A simple signal to confirm selection is actually happening.
            // (TerminalView keeps the selection internally; clipboard copy is handled by SwiftTerm.)
            print("[SwiftTerm] selectionChanged")
            #endif
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

// MARK: - Selectable Console Text View (mcwrap mode)

/// A native `NSTextView`-backed console that supports multi-line selection/copy reliably.
/// Used for `mcwrap` mode (where we already have a separate command input bar).
struct SelectableConsoleTextView: NSViewRepresentable {
    typealias NSViewType = NSScrollView

    let messages: [ConsoleMessage]
    let backgroundColor: NSColor

    init(messages: [ConsoleMessage], backgroundColor: NSColor = .clear) {
        self.messages = messages
        self.backgroundColor = backgroundColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.usesFindBar = true
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = backgroundColor != .clear
        textView.font = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .white
        textView.insertionPointColor = .clear
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = backgroundColor != .clear
        scrollView.backgroundColor = backgroundColor
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // Initial render
        context.coordinator.renderAll(messages: messages)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Keep references fresh
        context.coordinator.scrollView = nsView
        context.coordinator.textView = nsView.documentView as? NSTextView

        // Incremental append if possible
        context.coordinator.update(messages: messages)
    }

    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        private var renderedCount: Int = 0
        private var lastRenderedId: UUID?
        private let baseFont: NSFont = NSFont(name: "Menlo", size: 12) ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Persistent ANSI parser to maintain color state across messages
        // This is critical for truecolor gradients that span multiple lines
        private var ansiParser = ANSIParser()

        func update(messages: [ConsoleMessage]) {
            if messages.isEmpty {
                renderAll(messages: messages)
                return
            }

            // If list reset or shrunk, rerender fully.
            guard messages.count >= renderedCount else {
                renderAll(messages: messages)
                return
            }
            // If unchanged, do nothing.
            if messages.count == renderedCount {
                // If the last message changed (e.g., full refresh with same count), rerender.
                if messages.last?.id != lastRenderedId {
                    renderAll(messages: messages)
                }
                return
            }

            let newRange = renderedCount..<messages.count
            append(messages: Array(messages[newRange]))
            renderedCount = messages.count
            lastRenderedId = messages.last?.id
        }

        func renderAll(messages: [ConsoleMessage]) {
            guard let textView else { return }
            let shouldAutoScroll = shouldAutoScroll()
            let preservedOffset = shouldAutoScroll ? nil : currentScrollOffset()
            textView.textStorage?.setAttributedString(NSAttributedString())
            renderedCount = 0
            // Reset parser state when re-rendering from scratch
            ansiParser = ANSIParser()
            append(messages: messages, autoScroll: false)
            renderedCount = messages.count
            lastRenderedId = messages.last?.id
            if shouldAutoScroll {
                scrollToBottom()
            } else if let preservedOffset {
                restoreScrollOffset(preservedOffset)
            }
        }

        private func append(messages: [ConsoleMessage], autoScroll: Bool? = nil) {
            guard let textView else { return }
            let shouldAutoScroll = autoScroll ?? shouldAutoScroll()

            let storage = textView.textStorage ?? NSTextStorage()
            for message in messages {
                let line = render(message: message)
                let shouldDisplay = message.rawANSI ? hasVisibleContent(message.content) : true
                if shouldDisplay {
                    storage.append(line)
                    storage.append(NSAttributedString(string: "\n"))
                }
            }
            if textView.textStorage == nil {
                textView.textStorage?.setAttributedString(storage)
            }
            if shouldAutoScroll {
                scrollToBottom()
            }
        }

        private func render(message: ConsoleMessage) -> NSAttributedString {
            // mcwrap mode yields raw ANSI; fall back gracefully if not.
            let attr: AttributedString
            if message.rawANSI {
                if message.content.contains("\u{1B}") {
                    // Use the persistent parser to maintain color state across lines
                    // This is essential for truecolor gradients (like Oraxen's colored output)
                    attr = ansiParser.process(message.content)
                } else {
                    // Some PTY backends may emit Minecraft/Adventure formatting without ANSI escapes.
                    // Parse Minecraft color codes + MiniMessage/gradients so raw codes don't leak.
                    attr = MinecraftColorParser.parse(message.content, defaultColor: message.level.textColor)
                }
            } else {
                // Include timestamp/level for non-PTY sources.
                let line = "\(message.formattedTimestamp) \(message.content)"
                attr = MinecraftColorParser.parse(line, defaultColor: message.level.textColor)
            }
            return convertToAppKit(attr)
        }

        /// Convert a SwiftUI `AttributedString` (using `SwiftUI.Color`) into an AppKit `NSAttributedString`
        /// so colors survive rendering in `NSTextView`.
        private func convertToAppKit(_ attributed: AttributedString) -> NSAttributedString {
            let out = NSMutableAttributedString()

            for run in attributed.runs {
                let sub = AttributedString(attributed[run.range])
                let string = String(sub.characters)

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont
                ]

                if let fg = run.foregroundColor {
                    attrs[.foregroundColor] = NSColor(fg)
                }
                if let bg = run.backgroundColor {
                    attrs[.backgroundColor] = NSColor(bg)
                }
                if let underline = run.underlineStyle {
                    // SwiftUI uses `Text.LineStyle` here; map to a sensible AppKit style.
                    // (Our ANSI parser only ever emits single underline/strike anyway.)
                    _ = underline
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                if let strike = run.strikethroughStyle {
                    _ = strike
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }

                out.append(NSAttributedString(string: string, attributes: attrs))
            }

            return out
        }

        private func isNearBottom(threshold: CGFloat = 24) -> Bool {
            guard let scrollView else { return true }
            let contentView = scrollView.contentView
            guard let documentView = scrollView.documentView else { return true }
            let visibleMaxY = contentView.documentVisibleRect.maxY
            let docHeight = documentView.bounds.height
            return (docHeight - visibleMaxY) <= threshold
        }

        private func shouldAutoScroll() -> Bool {
            guard let textView else { return true }
            if let responder = textView.window?.firstResponder, responder === textView {
                return !hasActiveSelection() && isNearBottom()
            }
            return isNearBottom()
        }

        private func hasVisibleContent(_ text: String) -> Bool {
            let stripped = text.replacingOccurrences(
                of: "\u{1B}\\[[0-9;]*[A-Za-z]|\u{1B}\\][^\u{07}]*\u{07}|\u{1B}[^\\[\\]][A-Za-z]",
                with: "",
                options: .regularExpression
            )
            return !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private func hasActiveSelection() -> Bool {
            guard let textView else { return false }
            return textView.selectedRanges.contains { range in
                guard let r = range as? NSRange else { return false }
                return r.length > 0
            }
        }

        private func currentScrollOffset() -> CGFloat? {
            guard let scrollView else { return nil }
            return scrollView.contentView.bounds.origin.y
        }

        private func restoreScrollOffset(_ offset: CGFloat) {
            guard let scrollView, let documentView = scrollView.documentView else { return }
            let maxOffset = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
            let clamped = min(max(offset, 0), maxOffset)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scrollToBottom() {
            guard let scrollView else { return }
            guard let documentView = scrollView.documentView else { return }
            let bottomPoint = NSPoint(x: 0, y: max(0, documentView.bounds.height - scrollView.contentView.bounds.height))
            scrollView.contentView.scroll(to: bottomPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

// MARK: - Console View with SwiftTerm

struct SwiftTermConsoleView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var terminalController: SwiftTerminalController?
    @State private var isConnected = false
    @State private var hasRegisteredCallback = false
    @State private var pendingScrollback: String?
    @State private var hasFedScrollback = false
    @State private var needsScrollbackResync = false

    // MARK: - Local mouse reporting disable (for selection)

    /// Many terminal apps enable xterm mouse tracking (e.g. CSI ? 1000 h), which disables drag-selection.
    /// We aggressively disable mouse tracking *locally* in the emulator so users can always select text.
    private static let disableMouseReportingCSI =
        "\u{1B}[?1000l" +  // normal tracking
        "\u{1B}[?1002l" +  // button-event tracking
        "\u{1B}[?1003l" +  // any-event tracking
        "\u{1B}[?1005l" +  // UTF-8 coords
        "\u{1B}[?1006l" +  // SGR coords
        "\u{1B}[?1015l"    // urxvt coords

    private static let mouseParamsToStrip: Set<String> = ["1000", "1002", "1003", "1005", "1006", "1015"]

    private static let mouseReportingRegex: NSRegularExpression = {
        // Matches ESC [ ? <params> h/l (we'll decide whether to strip based on params)
        // Example: \u{1B}[?1000h or \u{1B}[?1000;1006h
        let pattern = "\u{1B}\\[\\?([0-9;]+)([hl])"
        // Fallback must be a valid regex; `NSRegularExpression()` can create an unusable instance and crash.
        return (try? NSRegularExpression(pattern: pattern)) ?? (try! NSRegularExpression(pattern: "(?!)"))
    }()

    private func disableMouseReportingLocally() {
        terminalController?.feed(text: Self.disableMouseReportingCSI)
    }

    private func sanitizeTerminalOutput(_ output: String) -> (sanitized: String, containedMouseEnable: Bool) {
        let ns = output as NSString
        let matches = Self.mouseReportingRegex.matches(in: output, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (output, false) }

        var shouldDisable = false
        var result = output

        // Remove matches in reverse order so ranges remain valid.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let paramsRange = match.range(at: 1)
            let hlRange = match.range(at: 2)
            guard paramsRange.location != NSNotFound, hlRange.location != NSNotFound else { continue }

            let params = ns.substring(with: paramsRange).split(separator: ";").map(String.init)
            let isMouseRelated = !Self.mouseParamsToStrip.intersection(params).isEmpty
            if !isMouseRelated { continue }

            // If remote is enabling mouse tracking, disable locally again.
            let hl = ns.substring(with: hlRange)
            if hl == "h" { shouldDisable = true }

            // Strip the sequence so SwiftTerm doesn't toggle selection behavior.
            result = (result as NSString).replacingCharacters(in: match.range, with: "") as String
        }

        return (result, shouldDisable)
    }

    // Warp-style input bar state
    @State private var commandText = ""
    @State private var showWarpUI = true  // Enable modern UI for mcwrap-pty
    @State private var bridgeCompletions: [CompletionItem] = []  // Completions from bridge service
    @State private var completionPreviewTask: Task<Void, Never>? = nil

    /// Check if the current server is using mcwrap-pty (which supports our enhanced UI)
    private var useEnhancedInputBar: Bool {
        guard let server = serverManager.selectedServer else { return false }
        // Only show enhanced input bar for mcwrap mode (our custom wrapper)
        return server.consoleMode == .ptyMcwrap
    }

    /// Fallback base commands (used when server commands haven't been discovered yet)
    private let fallbackCommands = [
        // Vanilla commands (always available)
        "help", "list", "stop", "restart", "reload",
        "gamemode", "gamerule", "give", "tp", "teleport",
        "time", "weather", "difficulty",
        "ban", "kick", "pardon", "op", "deop",
        "say", "tell", "msg", "whisper",
        "save-all", "save-on", "save-off",
        "whitelist", "seed", "spawn", "spawnpoint",
        "kill", "clear", "effect", "enchant",
        "summon", "setblock", "fill", "clone",
        "scoreboard", "team", "title", "bossbar",
        "plugins", "pl", "version", "ver"
    ]

    /// All known commands for the current server (dynamic + fallback)
    private var allCommands: [String] {
        // Reference published property to force SwiftUI to re-evaluate when command tree updates
        let updateCount = serverManager.commandTreeUpdateCount
        let logger = DebugLogger.shared

        guard let server = serverManager.selectedServer else {
            logger.log("allCommands: no server selected, returning fallback", category: .ui, verbose: true)
            return fallbackCommands
        }

        // Combine discovered commands with fallback
        var commands = Set(fallbackCommands)
        logger.log("allCommands: starting with \(fallbackCommands.count) fallback commands", category: .ui, verbose: true)

        // Add dynamically discovered commands from Brigadier tree
        if let tree = serverManager.commandTree[server.id] {
            let beforeCount = commands.count
            commands.formUnion(tree.rootCommands)
            let oCommands = tree.rootCommands.filter { $0.lowercased().hasPrefix("o") }
            logger.log("allCommands: added \(commands.count - beforeCount) from BrigadierTree (total root: \(tree.rootCommands.count), 'o' commands: \(oCommands.sorted()))", category: .ui)
        } else {
            logger.log("allCommands: no BrigadierTree for server \(server.id)", category: .ui)
        }

        // Also add commands from MCPanel Bridge's command tree (fetched via SFTP)
        let bridge = serverManager.bridgeService(for: server)
        if let bridgeTree = bridge.commandTree {
            let beforeCount = commands.count
            commands.formUnion(bridgeTree.commands.keys)
            let oCommands = bridgeTree.commands.keys.filter { $0.lowercased().hasPrefix("o") }
            logger.log("allCommands: added \(commands.count - beforeCount) from bridge (total: \(bridgeTree.commands.count), 'o' commands: \(oCommands.sorted())) updateCount=\(updateCount)", category: .ui)
        } else {
            logger.log("allCommands: bridge.commandTree is nil for server \(server.id)", category: .ui)
        }

        // Add root commands from history
        for cmd in commandHistory {
            let parts = cmd.split(separator: " ", maxSplits: 1)
            if let root = parts.first {
                commands.insert(String(root).lowercased())
            }
        }

        // Log final 'o' commands
        let finalOCommands = commands.filter { $0.lowercased().hasPrefix("o") }
        logger.log("allCommands: final count \(commands.count), 'o' commands: \(finalOCommands.sorted())", category: .ui)

        return commands.sorted()
    }

    /// Command history for current server
    private var commandHistory: [String] {
        guard let server = serverManager.selectedServer else { return [] }
        return serverManager.commandHistory[server.id]?.commands ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            if useEnhancedInputBar {
                // In mcwrap mode, use a native selectable text view (more reliable than terminal selection).
                SelectableConsoleTextView(messages: serverManager.selectedServerConsole)
            } else {
                // Terminal output area
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
            }

            // Warp-style input bar (only for mcwrap-pty mode)
            if useEnhancedInputBar {
                VStack(spacing: 8) {
                    // Command input bar
                    CommandInputBar(
                        command: $commandText,
                        onSubmit: { command in
                            submitCommand(command)
                        },
                        onTabComplete: {
                            // Request server-side completions from bridge
                            handleTabCompletion()
                        },
                        commandHistory: commandHistory,
                        baseSuggestions: allCommands,
                        bridgeCompletions: bridgeCompletions
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onChange(of: commandText) { _, newValue in
            // Live completion preview: compute completions locally as the user types (no Tab needed).
            updateCompletionPreview(buffer: newValue)
        }
        .onAppear {
            connectToServer()
        }
        .onDisappear {
            disconnectFromServer()
        }
        .onChange(of: serverManager.selectedServer?.id) { oldId, _ in
            // Reconnect when server changes
            hasRegisteredCallback = false
            hasFedScrollback = false
            pendingScrollback = nil
            needsScrollbackResync = false
            commandText = ""
            if let oldId,
               let oldServer = serverManager.servers.first(where: { $0.id == oldId }) {
                disconnectFromServer(oldServer)
            }
            connectToServer()
        }
        .onChange(of: serverManager.ptyConnected) { _, newValue in
            // Update isConnected state when PTY connection changes
            if let server = serverManager.selectedServer {
                let connected = newValue[server.id] == true
                isConnected = connected

                // Re-register callback when PTY reconnects (e.g., after restart) - only for terminal mode
                if connected && !hasRegisteredCallback && terminalController != nil {
                    print("[Console] PTY reconnected, re-registering callback")
                    hasRegisteredCallback = true
                    registerPTYCallback()
                    disableMouseReportingLocally()
                } else if !connected {
                    // Mark callback as unregistered so we re-register on reconnect
                    hasRegisteredCallback = false
                }
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // Register callback when terminal controller becomes available
            if let controller = terminalController, !hasRegisteredCallback, !useEnhancedInputBar {
                hasRegisteredCallback = true
                registerPTYCallback()
                let dims = controller.dimensions
                handleResize(cols: dims.cols, rows: dims.rows)
                // Ensure selection works by disabling mouse tracking in the emulator.
                disableMouseReportingLocally()
            }

            // Feed pending scrollback when terminal is ready
            if let controller = terminalController,
               let scrollback = pendingScrollback,
               !hasFedScrollback {
                hasFedScrollback = true
                pendingScrollback = nil
                // Sanitize scrollback too (it can contain mouse tracking toggles that break selection).
                let sanitized = sanitizeTerminalOutput(scrollback)
                // Convert \n to \r\n for proper terminal line breaks
                // Terminal emulators expect carriage return before newline
                let terminalScrollback = sanitized.sanitized.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\n", with: "\r\n")
                controller.feed(text: terminalScrollback)
                if sanitized.containedMouseEnable {
                    controller.feed(text: Self.disableMouseReportingCSI)
                }
            }
        }
    }

    // MARK: - Command Submission

    private func submitCommand(_ command: String) {
        guard let server = serverManager.selectedServer else { return }

        Task {
            await serverManager.sendCommand(command, to: server)
        }
    }

    private func updateCompletionPreview(buffer: String) {
        completionPreviewTask?.cancel()

        // Don't show preview when empty; CommandInputBar will fall back to history/base suggestions if needed.
        guard !buffer.isEmpty else {
            bridgeCompletions = []
            return
        }
        guard let server = serverManager.selectedServer else {
            bridgeCompletions = []
            return
        }

        let bridge = serverManager.bridgeService(for: server)
        // Debounce slightly to avoid thrashing while typing fast.
        completionPreviewTask = Task { @MainActor [buffer] in
            try? await Task.sleep(nanoseconds: 40_000_000) // 40ms
            guard !Task.isCancelled else { return }

            let completions = bridge.getCompletions(buffer: buffer)
            bridgeCompletions = completions.map {
                CompletionItem(
                    text: $0.text,
                    tooltip: $0.tooltip,
                    hasChildren: $0.hasChildren,
                    isTypeHint: $0.isTypeHint
                )
            }
        }
    }

    private func handleTabCompletion() {
        guard let server = serverManager.selectedServer else { return }

        // Use local command tree completion (no network calls)
        let bridge = serverManager.bridgeService(for: server)
        DebugLogger.shared.log("handleTabCompletion: buffer='\(commandText)'", category: .commands)
        let completions = bridge.getCompletions(buffer: commandText)
        DebugLogger.shared.log("handleTabCompletion: got \(completions.count) completions: \(completions.prefix(5).map { $0.text })", category: .commands)

        if !completions.isEmpty {
            if completions.count == 1 {
                // Single completion - auto-complete immediately
                let completion = completions[0]
                if completion.isTypeHint {
                    // Don't insert type-hints like "<greedy_string>" into the buffer.
                    // Show it as a non-insertable hint in the grid instead.
                    bridgeCompletions = [
                        CompletionItem(
                            text: completion.text,
                            tooltip: completion.tooltip,
                            hasChildren: completion.hasChildren,
                            isTypeHint: completion.isTypeHint
                        )
                    ]
                    return
                }
                let parts = commandText.components(separatedBy: " ")
                if parts.count > 1 {
                    var newParts = Array(parts.dropLast())
                    newParts.append(completion.text)
                    commandText = newParts.joined(separator: " ") + " "
                } else {
                    commandText = completion.text + " "
                }
                bridgeCompletions = []  // Clear completions

                // Auto-trigger next completion if this item has children
                if completion.hasChildren {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.handleTabCompletion()
                    }
                }
            } else {
                // Multiple completions - show murex-style grid with hasChildren and isTypeHint info
                bridgeCompletions = completions.map { CompletionItem(text: $0.text, tooltip: $0.tooltip, hasChildren: $0.hasChildren, isTypeHint: $0.isTypeHint) }
            }
        } else {
            bridgeCompletions = []
        }
    }

    /// Find the longest common prefix among strings
    private func longestCommonPrefix(_ strings: [String]) -> String? {
        guard let first = strings.first else { return nil }
        var prefix = first

        for string in strings.dropFirst() {
            while !string.lowercased().hasPrefix(prefix.lowercased()) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
            if prefix.isEmpty { return nil }
        }

        return prefix
    }

    private func connectToServer() {
        guard let server = serverManager.selectedServer else { return }

        Task {
            let wasConnected = await serverManager.isPTYConnected(for: server)

            // Detect available sessions
            await serverManager.detectPTYSessions(for: server)

            // Connect based on console mode
            if server.consoleMode == .logTail {
                await serverManager.loadConsole(for: server)
            } else {
                await serverManager.acquirePTY(for: server, consumer: .console)
            }

            let isNowConnected = await serverManager.isPTYConnected(for: server)

            await MainActor.run {
                isConnected = isNowConnected
                // Register callback after connection
                if !useEnhancedInputBar {
                    registerPTYCallback()
                }
            }

            let didConnect = !wasConnected && isNowConnected
            let shouldFetchScrollback = !useEnhancedInputBar
                && server.consoleMode != .logTail
                && (didConnect || needsScrollbackResync)

            // Fetch scrollback history after connecting (or when we missed output while hidden).
            // This gives us the console history to display and allows bridge detection.
            if shouldFetchScrollback, let scrollback = await serverManager.fetchScrollbackHistory(for: server) {
                await MainActor.run {
                    // Process scrollback through bridge service to detect any bridge messages
                    // This handles the case where bridge_ready event was sent before MCPanel connected
                    let bridge = serverManager.bridgeService(for: server)
                    let filteredScrollback = bridge.processOutput(scrollback, allowPartialBuffer: false)

                    // Store filtered scrollback to be fed when terminal is ready
                    // The timer will feed it once terminalController is available
                    pendingScrollback = filteredScrollback
                    needsScrollbackResync = false

                    // If bridge was detected, start command discovery
                    if bridge.bridgeDetected {
                        print("[Bridge] Detected MCPanel Bridge v\(bridge.bridgeVersion ?? "?") on \(bridge.platform ?? "unknown")")
                        serverManager.scrapeServerCommands(for: server)
                    }
                }
            }

            // Start dynamic command discovery in background if we don't have a command tree yet.
            await MainActor.run {
                let bridge = serverManager.bridgeService(for: server)
                if bridge.commandTree == nil {
                    serverManager.scrapeServerCommands(for: server)
                }
            }
        }
    }

    private func disconnectFromServer(_ server: Server? = nil) {
        guard let target = server ?? serverManager.selectedServer else { return }

        // Unregister callback
        serverManager.unregisterPTYOutputCallback(for: target)
        hasRegisteredCallback = false
        if !useEnhancedInputBar {
            needsScrollbackResync = true
        }

        serverManager.releasePTY(for: target, consumer: .console)
    }

    private func registerPTYCallback() {
        guard let server = serverManager.selectedServer,
              let controller = terminalController else { return }

        // Register callback to receive raw PTY output
        serverManager.registerPTYOutputCallback(for: server) { output in
            // Keep drag-selection working by stripping mouse tracking toggles and
            // re-disabling local mouse reporting if the remote tries to enable it.
            let sanitized = sanitizeTerminalOutput(output)
            if sanitized.containedMouseEnable {
                controller.feed(text: Self.disableMouseReportingCSI)
            }
            controller.feed(text: sanitized.sanitized)
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
