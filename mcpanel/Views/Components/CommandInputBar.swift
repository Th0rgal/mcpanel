//
//  CommandInputBar.swift
//  MCPanel
//
//  Murex-style command input bar with grid autocomplete and keyboard navigation
//

import SwiftUI
import AppKit

// MARK: - Tab-Capturing TextField

/// A TextField that properly captures Tab key presses and arrow keys on macOS.
/// Standard SwiftUI TextField doesn't handle Tab because it's used for focus navigation.
struct TabCapturingTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onLeftArrow: () -> Void
    var onRightArrow: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = TabTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        textField.textColor = .labelColor
        textField.onTab = onTab
        textField.onShiftTab = onShiftTab
        textField.onUpArrow = onUpArrow
        textField.onDownArrow = onDownArrow
        textField.onLeftArrow = onLeftArrow
        textField.onRightArrow = onRightArrow
        textField.onEscape = onEscape
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let tabField = nsView as? TabTextField {
            tabField.onTab = onTab
            tabField.onShiftTab = onShiftTab
            tabField.onUpArrow = onUpArrow
            tabField.onDownArrow = onDownArrow
            tabField.onLeftArrow = onLeftArrow
            tabField.onRightArrow = onRightArrow
            tabField.onEscape = onEscape
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TabCapturingTextField

        init(_ parent: TabCapturingTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onShiftTab()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            }
            if commandSelector == #selector(NSResponder.moveLeft(_:)) {
                parent.onLeftArrow()
                return true
            }
            if commandSelector == #selector(NSResponder.moveRight(_:)) {
                parent.onRightArrow()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}

/// Custom NSTextField subclass that captures Tab and arrow keys
class TabTextField: NSTextField {
    var onTab: (() -> Void)?
    var onShiftTab: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onDownArrow: (() -> Void)?
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onEscape: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 48 { // Tab key
            if event.modifierFlags.contains(.shift) {
                onShiftTab?()
            } else {
                onTab?()
            }
            return true
        }
        if event.keyCode == 53 { // Escape
            onEscape?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Completion Item

struct CompletionItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let tooltip: String?
    let isDirectory: Bool  // For visual indicator (trailing /)
    let hasChildren: Bool  // Whether this completion has subcommands/arguments
    let isTypeHint: Bool   // If true, this is a type hint (e.g., <itemid>), not a real value to insert

    init(text: String, tooltip: String? = nil, hasChildren: Bool = false, isTypeHint: Bool = false) {
        self.text = text
        self.tooltip = tooltip
        self.isDirectory = text.hasSuffix("/")
        self.hasChildren = hasChildren
        self.isTypeHint = isTypeHint
    }
}

// MARK: - Command Input Bar

struct CommandInputBar: View {
    @Binding var command: String
    var onSubmit: (String) -> Void
    var onTabComplete: (() -> Void)?
    var commandHistory: [String]
    var baseSuggestions: [String]

    // External completions from bridge service (set by parent)
    var bridgeCompletions: [CompletionItem] = []

    @State private var showHistory = false
    @State private var showCompletionGrid = false
    @State private var selectedIndex = 0
    @State private var completionItems: [CompletionItem] = []
    @State private var unfilteredCompletions: [CompletionItem] = []  // Store original completions for filtering
    @State private var columnCount = 4
    @FocusState private var isInputFocused: Bool

    /// Smart suggestions combining history and base commands
    private var filteredSuggestions: [CompletionItem] {
        guard !command.isEmpty else { return [] }
        let input = command.lowercased()
        let parts = input.split(separator: " ", maxSplits: 1)

        // History matches
        let historyMatches = commandHistory
            .filter { $0.lowercased().hasPrefix(input) }
            .reversed()
            .prefix(5)
            .map { CompletionItem(text: $0, tooltip: "history") }

        // If typing subcommand, only show history
        if parts.count > 1 {
            return Array(historyMatches)
        }

        // Base command matches
        let baseMatches = baseSuggestions
            .filter { $0.lowercased().hasPrefix(input) && !$0.contains(" ") }
            .sorted()
            .map { CompletionItem(text: $0) }

        // Combine and deduplicate
        var seen = Set<String>()
        var result: [CompletionItem] = []

        for item in historyMatches {
            if !seen.contains(item.text.lowercased()) {
                seen.insert(item.text.lowercased())
                result.append(item)
            }
        }

        for item in baseMatches {
            if !seen.contains(item.text.lowercased()) {
                seen.insert(item.text.lowercased())
                result.append(item)
            }
        }

        return Array(result.prefix(20))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Murex-style completion grid (above input)
            if showCompletionGrid && !completionItems.isEmpty {
                CompletionGridView(
                    items: completionItems,
                    selectedIndex: selectedIndex,
                    columnCount: columnCount,
                    onSelect: { item in
                        applyCompletion(item)
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Main input bar
            HStack(spacing: 12) {
                // Command prompt
                Text(">")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                // Input field with full keyboard handling
                TabCapturingTextField(
                    text: $command,
                    placeholder: "Enter command...",
                    onSubmit: submitCommand,
                    onTab: handleTab,
                    onShiftTab: handleShiftTab,
                    onUpArrow: handleUpArrow,
                    onDownArrow: handleDownArrow,
                    onLeftArrow: handleLeftArrow,
                    onRightArrow: handleRightArrow,
                    onEscape: handleEscape
                )
                .focused($isInputFocused)
                .onChange(of: command) { _, newValue in
                    // Update suggestions when typing
                    if showCompletionGrid && !unfilteredCompletions.isEmpty {
                        // Filter existing completions based on what user is typing
                        filterCompletions(buffer: newValue)
                    } else {
                        completionItems = filteredSuggestions
                        // Always show a live preview grid while typing (fallback suggestions).
                        showCompletionGrid = !completionItems.isEmpty && !showHistory
                        if showCompletionGrid {
                            updateColumnCount()
                        }
                    }
                    selectedIndex = 0
                }
                .onChange(of: bridgeCompletions) { _, newCompletions in
                    // When bridge completions arrive, show them
                    if !newCompletions.isEmpty {
                        // Debug: log what we received
                        print("[Bridge] Received \(newCompletions.count) completions:")
                        for item in newCompletions.prefix(10) {
                            print("  - '\(item.text)' isTypeHint=\(item.isTypeHint) hasChildren=\(item.hasChildren)")
                        }

                        // Prefer real (insertable) completions. Only show type hints if there are no real values.
                        let real = newCompletions.filter { !$0.isTypeHint }
                        let base = real.isEmpty ? newCompletions : real

                        unfilteredCompletions = base
                        completionItems = base
                        showCompletionGrid = true
                        selectedIndex = 0
                        updateColumnCount()
                    } else {
                        // No bridge completions available; fall back to history/base suggestions.
                        unfilteredCompletions = []
                        completionItems = filteredSuggestions
                        showCompletionGrid = !completionItems.isEmpty && !showHistory
                        selectedIndex = 0
                        if showCompletionGrid {
                            updateColumnCount()
                        }
                    }
                }

                // Quick action buttons
                HStack(spacing: 8) {
                    // History button
                    Button {
                        showHistory.toggle()
                        showCompletionGrid = false
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Command History")
                    .popover(isPresented: $showHistory) {
                        HistoryPopover(
                            history: commandHistory,
                            onSelect: { cmd in
                                command = cmd
                                showHistory = false
                            }
                        )
                    }

                    // Send button
                    Button {
                        submitCommand()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                            Text("Send")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(command.isEmpty ? Color.gray.opacity(0.5) : Color.accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(command.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: -2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .animation(.easeOut(duration: 0.15), value: showCompletionGrid)
    }

    // MARK: - Column Count Calculation

    private func updateColumnCount() {
        // Calculate optimal column count based on item lengths
        let maxLength = completionItems.map { $0.text.count }.max() ?? 10
        if maxLength > 25 {
            columnCount = 2
        } else if maxLength > 15 {
            columnCount = 3
        } else if maxLength > 10 {
            columnCount = 4
        } else {
            columnCount = 5
        }
    }

    // MARK: - Actions

    private func submitCommand() {
        guard !command.isEmpty else { return }

        // If completion grid is showing with selection, confirm selection with Enter
        if showCompletionGrid && !completionItems.isEmpty {
            applyCompletion(completionItems[selectedIndex])
            return
        }

        onSubmit(command)
        command = ""
        showCompletionGrid = false
        completionItems = []
    }

    private func handleTab() {
        if showCompletionGrid && !completionItems.isEmpty {
            if completionItems.count == 1 {
                // If there's only one option, accept it immediately (same as Enter).
                applyCompletion(completionItems[0])
            } else {
                // Tab navigates forward through completions (like Shift+Tab goes backward)
                selectedIndex = (selectedIndex + 1) % completionItems.count
            }
        } else {
            // Not showing completions - request them from bridge
            onTabComplete?()
        }
    }

    private func handleShiftTab() {
        if showCompletionGrid && !completionItems.isEmpty {
            // Move selection backward
            selectedIndex = (selectedIndex - 1 + completionItems.count) % completionItems.count
        }
    }

    private func handleUpArrow() {
        guard showCompletionGrid && !completionItems.isEmpty else { return }
        // Move up one row
        let newIndex = selectedIndex - columnCount
        if newIndex >= 0 {
            selectedIndex = newIndex
        }
    }

    private func handleDownArrow() {
        guard showCompletionGrid && !completionItems.isEmpty else { return }
        // Move down one row
        let newIndex = selectedIndex + columnCount
        if newIndex < completionItems.count {
            selectedIndex = newIndex
        }
    }

    private func handleLeftArrow() {
        guard showCompletionGrid && !completionItems.isEmpty else { return }
        // Move left one column (with wrap)
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    private func handleRightArrow() {
        guard showCompletionGrid && !completionItems.isEmpty else { return }
        // Move right one column
        if selectedIndex < completionItems.count - 1 {
            selectedIndex += 1
        }
    }

    private func handleEscape() {
        if showCompletionGrid {
            showCompletionGrid = false
            completionItems = []
            unfilteredCompletions = []
        }
    }

    /// Filter completions based on what user has typed in the current argument
    private func filterCompletions(buffer: String) {
        // Get the last part of the command (what user is currently typing)
        let parts = buffer.split(separator: " ", omittingEmptySubsequences: false)
        let currentTyping = parts.last.map(String.init) ?? ""
        let prefix = currentTyping.lowercased()

        print("[Filter] command='\(buffer)', parts=\(parts.count), currentTyping='\(currentTyping)', unfilteredCount=\(unfilteredCompletions.count)")

        if prefix.isEmpty {
            // Nothing typed yet for this argument - show all
            completionItems = unfilteredCompletions
            print("[Filter] prefix empty, restored \(completionItems.count) items")
        } else {
            // Filter to items that start with what user typed
            // Don't filter type hints out - but don't force them to stay either
            completionItems = unfilteredCompletions.filter { item in
                item.text.lowercased().hasPrefix(prefix)
            }
            print("[Filter] prefix='\(prefix)', filtered to \(completionItems.count) items")
        }

        // If all items got filtered out, close the grid
        if completionItems.isEmpty {
            showCompletionGrid = false
            unfilteredCompletions = []
            print("[Filter] no matches, closing grid")
        } else {
            updateColumnCount()
        }
    }

    private func applyCompletion(_ item: CompletionItem) {
        // If it's a type hint, don't insert it - just close the grid and let user type
        if item.isTypeHint {
            showCompletionGrid = false
            completionItems = []
            unfilteredCompletions = []
            // Don't modify the command - user needs to type their own value
            return
        }

        // Get the current command parts
        let parts = command.split(separator: " ", omittingEmptySubsequences: false)

        if parts.count <= 1 {
            // Replacing root command
            command = item.text + " "
        } else {
            // Replacing last part (subcommand/argument)
            var newParts = Array(parts.dropLast())
            newParts.append(Substring(item.text))
            command = newParts.joined(separator: " ") + " "
        }

        showCompletionGrid = false
        completionItems = []
        unfilteredCompletions = []

        // Auto-trigger next completion if this item has children (subcommands)
        if item.hasChildren {
            // Small delay to let the command text update propagate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.onTabComplete?()
            }
        }
    }
}

// MARK: - Murex-Style Completion Grid

struct CompletionGridView: View {
    let items: [CompletionItem]
    let selectedIndex: Int
    let columnCount: Int
    var onSelect: (CompletionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with keyboard hints
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    KeyHint(key: "Tab")
                    Text("next")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    KeyHint(key: "↑↓←→")
                    Text("navigate")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    KeyHint(key: "↵")
                    Text("accept")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    KeyHint(key: "Esc")
                    Text("cancel")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(items.count) items")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Grid of completions
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount),
                alignment: .leading,
                spacing: 2
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    CompletionCell(
                        item: item,
                        isSelected: index == selectedIndex
                    )
                    .onTapGesture {
                        onSelect(item)
                    }
                }
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Completion Cell

struct CompletionCell: View {
    let item: CompletionItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(item.text)
                .font(.system(size: 12, design: .monospaced))
                .italic(item.isTypeHint)  // Italicize type hints
                .foregroundColor(textColor)
                .lineLimit(1)
                .truncationMode(.middle)

            // Show indicator for type hints
            if item.isTypeHint {
                Text("(type)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor)
        )
        .help(item.tooltip ?? item.text)
    }

    private var textColor: Color {
        if isSelected {
            return .white
        } else if item.isTypeHint {
            return .secondary  // Grey out type hints
        } else {
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return item.isTypeHint ? Color.orange.opacity(0.7) : Color.accentColor
        }
        return Color.clear
    }
}

// MARK: - Key Hint Badge

struct KeyHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}

// MARK: - History Popover

struct HistoryPopover: View {
    let history: [String]
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Commands")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if history.isEmpty {
                Text("No command history")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(history.reversed().prefix(20).enumerated()), id: \.offset) { _, cmd in
                            Button {
                                onSelect(cmd)
                            } label: {
                                HStack {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)

                                    Text(cmd)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 300)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        CommandInputBar(
            command: .constant("oraxen "),
            onSubmit: { _ in },
            onTabComplete: nil,
            commandHistory: ["help", "list", "gamemode creative"],
            baseSuggestions: ["gamemode", "gamerule", "give", "tp", "time", "weather", "oraxen"],
            bridgeCompletions: [
                CompletionItem(text: "admin"),
                CompletionItem(text: "blockinfo"),
                CompletionItem(text: "debug"),
                CompletionItem(text: "dump_log"),
                CompletionItem(text: "dye"),
                CompletionItem(text: "emojis"),
                CompletionItem(text: "give"),
                CompletionItem(text: "glyphinfo"),
                CompletionItem(text: "h_md"),
                CompletionItem(text: "highest_modeldata"),
                CompletionItem(text: "pack"),
                CompletionItem(text: "reload"),
            ]
        )
        .padding()
    }
    .frame(width: 600, height: 400)
    .background(Color(nsColor: .windowBackgroundColor))
}
