//
//  CommandInputBar.swift
//  MCPanel
//
//  Warp-style command input bar with autocomplete and history
//

import SwiftUI

// MARK: - Command Input Bar

struct CommandInputBar: View {
    @Binding var command: String
    var onSubmit: (String) -> Void
    var onTabComplete: (() -> Void)?
    var commandHistory: [String]
    var baseSuggestions: [String]  // Base commands only (no subcommands hardcoded)
    var isConnected: Bool

    @State private var showHistory = false
    @State private var showSuggestions = false
    @State private var selectedSuggestionIndex = 0
    @FocusState private var isInputFocused: Bool

    /// Smart suggestions that prioritize history and group by root command
    private var filteredSuggestions: [String] {
        guard !command.isEmpty else { return [] }
        let input = command.lowercased()

        // Split input to detect if user is typing a subcommand
        let parts = input.split(separator: " ", maxSplits: 1)

        // 1. First, get matches from command history (most relevant)
        let historyMatches = commandHistory
            .filter { $0.lowercased().hasPrefix(input) }
            .reversed()  // Most recent first
            .prefix(3)

        // 2. If user has typed a space (looking for subcommands), suggest from history only
        //    This encourages using Tab for server-side completion
        if parts.count > 1 {
            // User is typing subcommand - only show history matches
            // Tab completion will get server-side suggestions
            return Array(historyMatches)
        }

        // 3. For root commands, show base suggestions that match
        let baseMatches = baseSuggestions
            .filter { $0.lowercased().hasPrefix(input) }
            .filter { !$0.contains(" ") }  // Only root commands, no subcommands
            .sorted()

        // 4. Combine: history first (deduplicated), then base suggestions
        var seen = Set<String>()
        var result: [String] = []

        for cmd in historyMatches {
            let normalized = cmd.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(cmd)
            }
        }

        for cmd in baseMatches {
            let normalized = cmd.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(cmd)
            }
        }

        return Array(result.prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Suggestions dropdown (above input)
            if showSuggestions {
                if !filteredSuggestions.isEmpty {
                    SuggestionsDropdown(
                        suggestions: filteredSuggestions,
                        selectedIndex: selectedSuggestionIndex,
                        onSelect: { suggestion in
                            command = suggestion + " "  // Add space to encourage subcommand input
                            showSuggestions = true  // Keep showing for potential subcommands from history
                            selectedSuggestionIndex = 0
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if command.contains(" ") {
                    // Show Tab hint when typing subcommands with no history matches
                    TabCompletionHint()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Main input bar
            HStack(spacing: 12) {
                // Command prompt indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)

                    Text(">")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Input field
                TextField("Enter command...", text: $command)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .focused($isInputFocused)
                    .onSubmit {
                        submitCommand()
                    }
                    .onChange(of: command) { _, newValue in
                        // Show suggestions when typing
                        showSuggestions = !newValue.isEmpty
                        selectedSuggestionIndex = 0
                    }
                    .onKeyPress(.tab) {
                        handleTabCompletion()
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        if showSuggestions && !filteredSuggestions.isEmpty {
                            selectedSuggestionIndex = max(0, selectedSuggestionIndex - 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        if showSuggestions && !filteredSuggestions.isEmpty {
                            selectedSuggestionIndex = min(filteredSuggestions.count - 1, selectedSuggestionIndex + 1)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        showSuggestions = false
                        showHistory = false
                        return .handled
                    }

                // Quick action buttons
                HStack(spacing: 8) {
                    // History button
                    Button {
                        showHistory.toggle()
                        showSuggestions = false
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
                    .keyboardShortcut(.return, modifiers: [])
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
        .animation(.easeOut(duration: 0.15), value: showSuggestions)
    }

    // MARK: - Actions

    private func submitCommand() {
        guard !command.isEmpty else { return }
        onSubmit(command)
        command = ""
        showSuggestions = false
    }

    private func handleTabCompletion() {
        if showSuggestions && !filteredSuggestions.isEmpty {
            // Use selected suggestion
            command = filteredSuggestions[selectedSuggestionIndex]
            showSuggestions = false
        } else {
            // Trigger external tab completion (for server-side)
            onTabComplete?()
        }
    }
}

// MARK: - Tab Completion Hint

struct TabCompletionHint: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text("Press")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text("Tab")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.1))
                )

            Text("for server completions")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Suggestions Dropdown

struct SuggestionsDropdown: View {
    let suggestions: [String]
    let selectedIndex: Int
    var onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.prefix(8).enumerated()), id: \.offset) { index, suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack {
                        Image(systemName: commandIcon(for: suggestion))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        Text(suggestion)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.primary)

                        Spacer()

                        if index == selectedIndex {
                            Text("↵")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func commandIcon(for command: String) -> String {
        let cmd = command.lowercased()
        // Vanilla commands
        if cmd.hasPrefix("give") || cmd.hasPrefix("iagive") { return "gift" }
        if cmd.hasPrefix("tp") || cmd.hasPrefix("teleport") || cmd.hasPrefix("tpa") { return "location" }
        if cmd.hasPrefix("gamemode") { return "gamecontroller" }
        if cmd.hasPrefix("time") { return "clock" }
        if cmd.hasPrefix("weather") { return "cloud.sun" }
        if cmd.hasPrefix("ban") || cmd.hasPrefix("kick") { return "xmark.circle" }
        if cmd.hasPrefix("op") || cmd.hasPrefix("deop") { return "star" }
        if cmd.hasPrefix("say") || cmd.hasPrefix("tell") || cmd.hasPrefix("msg") || cmd.hasPrefix("broadcast") { return "bubble.left" }
        if cmd.hasPrefix("stop") { return "stop.circle" }
        if cmd.hasPrefix("reload") || cmd.hasPrefix("iareload") { return "arrow.clockwise" }
        if cmd.hasPrefix("help") { return "questionmark.circle" }
        if cmd.hasPrefix("list") { return "person.2" }
        if cmd.hasPrefix("whitelist") { return "checklist" }
        if cmd.hasPrefix("save") { return "square.and.arrow.down" }

        // Plugin commands
        if cmd.hasPrefix("oraxen") || cmd.hasPrefix("oxen") || cmd == "o" { return "cube.box" }
        if cmd.hasPrefix("itemsadder") || cmd.hasPrefix("ia") { return "cube.box.fill" }
        if cmd.hasPrefix("luckperms") || cmd.hasPrefix("lp") || cmd.hasPrefix("perm") { return "lock.shield" }
        if cmd.hasPrefix("worldedit") || cmd.hasPrefix("we") || cmd.hasPrefix("pos") || cmd.hasPrefix("set") || cmd.hasPrefix("replace") { return "square.on.square" }
        if cmd.hasPrefix("worldguard") || cmd.hasPrefix("wg") || cmd.hasPrefix("region") || cmd.hasPrefix("rg") { return "shield" }
        if cmd.hasPrefix("essentials") || cmd.hasPrefix("eco") || cmd.hasPrefix("bal") || cmd.hasPrefix("pay") { return "dollarsign.circle" }
        if cmd.hasPrefix("home") || cmd.hasPrefix("sethome") || cmd.hasPrefix("spawn") { return "house" }
        if cmd.hasPrefix("warp") || cmd.hasPrefix("setwarp") { return "signpost.right" }
        if cmd.hasPrefix("fly") { return "airplane" }
        if cmd.hasPrefix("heal") || cmd.hasPrefix("feed") { return "heart" }
        if cmd.hasPrefix("vanish") || cmd.hasPrefix("god") { return "eye.slash" }
        if cmd.hasPrefix("coreprotect") || cmd.hasPrefix("co") { return "clock.arrow.circlepath" }
        if cmd.hasPrefix("dynmap") || cmd.hasPrefix("dmap") { return "map" }
        if cmd.hasPrefix("citizens") || cmd.hasPrefix("npc") { return "person.crop.circle" }
        if cmd.hasPrefix("mv") || cmd.hasPrefix("multiverse") { return "globe" }
        if cmd.hasPrefix("towny") || cmd.hasPrefix("town") || cmd.hasPrefix("nation") { return "building.2" }
        if cmd.hasPrefix("factions") || cmd == "f" { return "flag" }
        if cmd.hasPrefix("mcmmo") || cmd.hasPrefix("mcstats") { return "chart.bar" }
        if cmd.hasPrefix("jobs") { return "briefcase" }
        if cmd.hasPrefix("claim") || cmd.hasPrefix("trust") { return "rectangle.badge.checkmark" }
        if cmd.hasPrefix("spark") || cmd.hasPrefix("timings") || cmd.hasPrefix("tps") || cmd.hasPrefix("mspt") { return "gauge.medium" }
        if cmd.hasPrefix("plugins") || cmd.hasPrefix("pl") || cmd.hasPrefix("plugman") { return "puzzlepiece.extension" }
        if cmd.hasPrefix("geyser") || cmd.hasPrefix("floodgate") { return "point.3.connected.trianglepath.dotted" }
        if cmd.hasPrefix("paper") || cmd.hasPrefix("spigot") || cmd.hasPrefix("version") || cmd.hasPrefix("ver") { return "info.circle" }

        return "terminal"
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
                            .background(Color.clear)
                            .onHover { hovering in
                                // Visual feedback handled by button style
                            }
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

// MARK: - Quick Actions Bar

struct QuickActionsBar: View {
    var onAction: (QuickAction) -> Void
    var serverStatus: ServerStatus

    enum QuickAction: String, CaseIterable {
        case stop = "Stop"
        case restart = "Restart"
        case reload = "Reload"
        case players = "Players"
        case tps = "TPS"

        var icon: String {
            switch self {
            case .stop: return "stop.circle.fill"
            case .restart: return "arrow.clockwise.circle.fill"
            case .reload: return "arrow.triangle.2.circlepath"
            case .players: return "person.2.fill"
            case .tps: return "gauge.medium"
            }
        }

        var color: Color {
            switch self {
            case .stop: return .red
            case .restart: return .orange
            case .reload: return .blue
            case .players: return .green
            case .tps: return .purple
            }
        }
    }

    enum ServerStatus {
        case online
        case offline
        case starting
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(QuickAction.allCases, id: \.self) { action in
                Button {
                    onAction(action)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: action.icon)
                            .font(.system(size: 11))
                        Text(action.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(action.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(action.color.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .disabled(serverStatus == .offline && action != .restart)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        CommandInputBar(
            command: .constant("gamemode"),
            onSubmit: { _ in },
            onTabComplete: nil,
            commandHistory: ["help", "list", "gamemode creative"],
            baseSuggestions: ["gamemode", "gamerule", "give", "tp", "time", "weather"],
            isConnected: true
        )
        .padding()
    }
    .frame(width: 600, height: 400)
    .background(Color(nsColor: .windowBackgroundColor))
}
