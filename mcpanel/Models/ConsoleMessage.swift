//
//  ConsoleMessage.swift
//  MCPanel
//
//  Model representing a console log message
//

import Foundation
import SwiftUI

// MARK: - Console Message Level

enum ConsoleLevel: String, Codable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case debug = "DEBUG"
    case player = "PLAYER"
    case plugin = "PLUGIN"
    case command = "COMMAND"  // User-sent command

    var color: Color {
        switch self {
        case .info: return .primary
        case .warn: return .yellow
        case .error: return .red
        case .debug: return .gray
        case .player: return .cyan
        case .plugin: return .green
        case .command: return .orange
        }
    }

    // Color for the status dot indicator
    var dotColor: Color {
        switch self {
        case .info: return Color(hex: "AAAAAA")    // Gray
        case .warn: return Color(hex: "FFAA00")    // Orange/Gold
        case .error: return Color(hex: "FF5555")   // Red
        case .debug: return Color(hex: "555555")   // Dark gray
        case .player: return Color(hex: "55FFFF")  // Cyan
        case .plugin: return Color(hex: "55FF55")  // Green
        case .command: return Color(hex: "FFAA00") // Gold
        }
    }

    // Text color for the main content
    var textColor: Color {
        switch self {
        case .info: return Color(hex: "DDDDDD")    // Light gray (readable)
        case .warn: return Color(hex: "FFFF55")    // Yellow
        case .error: return Color(hex: "FF5555")   // Red
        case .debug: return Color(hex: "888888")   // Medium gray
        case .player: return Color(hex: "FFFFFF")  // White (for chat)
        case .plugin: return Color(hex: "AAFFAA")  // Light green
        case .command: return Color(hex: "FFAA00") // Gold
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .debug: return "ant"
        case .player: return "person.fill"
        case .plugin: return "puzzlepiece.extension"
        case .command: return "chevron.right"
        }
    }
}

// MARK: - Console Message

struct ConsoleMessage: Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let level: ConsoleLevel
    let content: String
    let source: String?  // Plugin name or system component
    let rawANSI: Bool    // If true, content contains raw ANSI sequences (from PTY)
    let isScrollback: Bool  // True when sourced from scrollback/history

    // MARK: - Computed Properties

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    var fullTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ConsoleLevel = .info,
        content: String,
        source: String? = nil,
        rawANSI: Bool = false,
        isScrollback: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.content = content
        self.source = source
        self.rawANSI = rawANSI
        self.isScrollback = isScrollback
    }

    /// Parse a Minecraft server log line
    /// Format: [HH:mm:ss INFO]: Message
    /// or: [HH:mm:ss] [Server thread/INFO]: Message
    static func parse(_ line: String) -> ConsoleMessage {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ConsoleMessage(content: line)
        }

        var timestamp = Date()
        var level: ConsoleLevel = .info
        var content = trimmed
        var source: String?

        // Try to parse timestamp [HH:mm:ss]
        if let timestampMatch = trimmed.range(of: #"\[(\d{2}:\d{2}:\d{2})\]"#, options: .regularExpression) {
            let timeStr = String(trimmed[timestampMatch]).dropFirst().dropLast()
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"

            // Use today's date with the parsed time
            if let parsedTime = formatter.date(from: String(timeStr)) {
                let calendar = Calendar.current
                let now = Date()
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: parsedTime)
                components.hour = timeComponents.hour
                components.minute = timeComponents.minute
                components.second = timeComponents.second
                timestamp = calendar.date(from: components) ?? now
            }

            content = String(trimmed[timestampMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Try to parse level INFO/WARN/ERROR
        let levelPatterns: [(pattern: String, level: ConsoleLevel)] = [
            (#"^\[?.*?INFO\]?:?\s*"#, .info),
            (#"^\[?.*?WARN(ING)?\]?:?\s*"#, .warn),
            (#"^\[?.*?ERROR\]?:?\s*"#, .error),
            (#"^\[?.*?DEBUG\]?:?\s*"#, .debug)
        ]

        for (pattern, lvl) in levelPatterns {
            if let range = content.range(of: pattern, options: .regularExpression) {
                level = lvl
                content = String(content[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Detect player messages: <PlayerName> message or PlayerName joined/left
        if content.hasPrefix("<") && content.contains(">") {
            level = .player
        } else if content.contains("joined the game") || content.contains("left the game") {
            level = .player
        } else if content.contains("logged in with entity") || content.contains("lost connection") {
            level = .player
        }

        // Detect plugin source from bracket prefix: [PluginName] message
        if let pluginMatch = content.range(of: #"^\[([^\]]+)\]\s*"#, options: .regularExpression) {
            let bracket = String(content[pluginMatch])
            if let nameStart = bracket.firstIndex(of: "["),
               let nameEnd = bracket.firstIndex(of: "]") {
                source = String(bracket[bracket.index(after: nameStart)..<nameEnd])
                // Only mark as plugin if it's not a thread name
                if !source!.contains("thread") && !source!.contains("Thread") {
                    level = .plugin
                }
            }
            content = String(content[pluginMatch.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        return ConsoleMessage(
            timestamp: timestamp,
            level: level,
            content: content,
            source: source
        )
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ConsoleMessage, rhs: ConsoleMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Minecraft Color Parser

struct MinecraftColorParser {
    // Standard Minecraft color codes (§ followed by character)
    static let colorCodes: [Character: String] = [
        "0": "000000",  // Black
        "1": "0000AA",  // Dark Blue
        "2": "00AA00",  // Dark Green
        "3": "00AAAA",  // Dark Aqua
        "4": "AA0000",  // Dark Red
        "5": "AA00AA",  // Dark Purple
        "6": "FFAA00",  // Gold
        "7": "AAAAAA",  // Gray
        "8": "555555",  // Dark Gray
        "9": "5555FF",  // Blue
        "a": "55FF55",  // Green
        "b": "55FFFF",  // Aqua
        "c": "FF5555",  // Red
        "d": "FF55FF",  // Light Purple
        "e": "FFFF55",  // Yellow
        "f": "FFFFFF",  // White
    ]

    // Named colors for MiniMessage
    static let namedColors: [String: String] = [
        "black": "000000", "dark_blue": "0000AA", "dark_green": "00AA00",
        "dark_aqua": "00AAAA", "dark_red": "AA0000", "dark_purple": "AA00AA",
        "gold": "FFAA00", "gray": "AAAAAA", "grey": "AAAAAA",
        "dark_gray": "555555", "dark_grey": "555555",
        "blue": "5555FF", "green": "55FF55", "aqua": "55FFFF",
        "red": "FF5555", "light_purple": "FF55FF", "yellow": "FFFF55",
        "white": "FFFFFF", "orange": "FF8800", "pink": "FF55FF"
    ]

    // Formatting codes
    static let formatCodes: Set<Character> = ["k", "l", "m", "n", "o", "r"]

    /// Parse Minecraft color codes and return an AttributedString
    /// Supports:
    /// - ANSI escape sequences (from RCON output)
    /// - § color codes (§a, §b, etc.)
    /// - Hex codes: &#RRGGBB, <#RRGGBB>, §x§R§R§G§G§B§B
    /// - MiniMessage tags: <color:#RRGGBB>, <#RRGGBB>
    /// - MiniMessage gradients: <gradient:color1:color2>text</gradient>
    /// - MiniMessage rainbow: <rainbow>text</rainbow>
    static func parse(_ text: String, defaultColor: Color) -> AttributedString {
        // Check if text contains ANSI escape sequences (ESC character)
        if text.contains("\u{1B}") {
            // Use the proper state machine ANSI parser
            return ANSIParser.parse(text)
        }

        // Try to process gradient and rainbow tags
        if let processedText = processGradientTags(text, defaultColor: defaultColor) {
            return processedText
        }

        // If no gradient processing happened, use standard Minecraft color parsing
        return parseStandard(text, defaultColor: defaultColor)
    }

    /// Process gradient and rainbow tags, returning AttributedString or nil if no gradients found
    private static func processGradientTags(_ text: String, defaultColor: Color) -> AttributedString? {
        var result = AttributedString()
        var index = text.startIndex
        var hasGradient = false

        while index < text.endIndex {
            // Look for gradient or rainbow tag
            if text[index] == "<" {
                // Check for <gradient:...>
                if let gradientResult = parseGradientTag(text, from: index, defaultColor: defaultColor) {
                    // Parse any content before the gradient with standard parsing
                    result.append(gradientResult.attributed)
                    index = gradientResult.endIndex
                    hasGradient = true
                    continue
                }

                // Check for <rainbow...>
                if let rainbowResult = parseRainbowTag(text, from: index, defaultColor: defaultColor) {
                    result.append(rainbowResult.attributed)
                    index = rainbowResult.endIndex
                    hasGradient = true
                    continue
                }
            }

            // No gradient/rainbow tag found, parse character with standard method
            let (attrChar, nextIndex) = parseCharacter(text, at: index, defaultColor: defaultColor, currentColor: defaultColor, formatting: Formatting())
            result.append(attrChar)
            index = nextIndex
        }

        return hasGradient ? result : nil
    }

    /// Parse a gradient tag: <gradient:color1:color2:...>text</gradient>
    private static func parseGradientTag(_ text: String, from startIndex: String.Index, defaultColor: Color) -> (attributed: AttributedString, endIndex: String.Index)? {
        // Check if it starts with <gradient
        let remaining = String(text[startIndex...])
        guard remaining.hasPrefix("<gradient") else { return nil }

        // Find the closing >
        guard let tagEndIndex = remaining.firstIndex(of: ">") else { return nil }
        let tagContent = String(remaining[remaining.index(after: remaining.startIndex)..<tagEndIndex])

        // Parse gradient colors from tag content like "gradient:color1:color2"
        let parts = tagContent.split(separator: ":")
        guard parts.count >= 2, parts[0] == "gradient" else { return nil }

        // Extract colors
        var colors: [(r: Double, g: Double, b: Double)] = []
        for i in 1..<parts.count {
            let colorStr = String(parts[i]).trimmingCharacters(in: .whitespaces)
            if let rgb = parseColorToRGB(colorStr) {
                colors.append(rgb)
            }
        }

        guard colors.count >= 2 else { return nil }

        // Find the content between <gradient:...> and </gradient>
        let afterTag = String(remaining[remaining.index(after: tagEndIndex)...])
        guard let closeTagRange = afterTag.range(of: "</gradient>", options: .caseInsensitive) else {
            // No closing tag, try to find end of line or just colorize rest
            return nil
        }

        let gradientContent = String(afterTag[..<closeTagRange.lowerBound])

        // Strip any nested color codes from the content for length calculation
        let strippedContent = stripColorCodes(gradientContent)
        let contentLength = strippedContent.count

        guard contentLength > 0 else { return nil }

        // Apply gradient colors to each character
        var result = AttributedString()
        var charIndex = 0

        for char in strippedContent {
            let progress = contentLength > 1 ? Double(charIndex) / Double(contentLength - 1) : 0.5
            let color = interpolateGradient(colors: colors, progress: progress)

            var attrChar = AttributedString(String(char))
            attrChar.foregroundColor = color
            result.append(attrChar)
            charIndex += 1
        }

        // Calculate the end index in the original text
        let startOffset = text.distance(from: text.startIndex, to: startIndex)
        let totalLength = "<gradient".count + (tagContent.count - "gradient".count) + ">".count + gradientContent.count + "</gradient>".count
        let endIndex = text.index(text.startIndex, offsetBy: startOffset + totalLength, limitedBy: text.endIndex) ?? text.endIndex

        return (result, endIndex)
    }

    /// Parse a rainbow tag: <rainbow>text</rainbow>
    private static func parseRainbowTag(_ text: String, from startIndex: String.Index, defaultColor: Color) -> (attributed: AttributedString, endIndex: String.Index)? {
        let remaining = String(text[startIndex...])
        guard remaining.hasPrefix("<rainbow") else { return nil }

        // Find the closing >
        guard let tagEndIndex = remaining.firstIndex(of: ">") else { return nil }

        // Find content between <rainbow...> and </rainbow>
        let afterTag = String(remaining[remaining.index(after: tagEndIndex)...])
        guard let closeTagRange = afterTag.range(of: "</rainbow>", options: .caseInsensitive) else {
            return nil
        }

        let rainbowContent = String(afterTag[..<closeTagRange.lowerBound])
        let strippedContent = stripColorCodes(rainbowContent)
        let contentLength = strippedContent.count

        guard contentLength > 0 else { return nil }

        // Rainbow colors
        let rainbowColors: [(r: Double, g: Double, b: Double)] = [
            (1.0, 0.0, 0.0),    // Red
            (1.0, 0.5, 0.0),    // Orange
            (1.0, 1.0, 0.0),    // Yellow
            (0.0, 1.0, 0.0),    // Green
            (0.0, 1.0, 1.0),    // Cyan
            (0.0, 0.0, 1.0),    // Blue
            (0.5, 0.0, 1.0),    // Purple
            (1.0, 0.0, 0.5),    // Pink
        ]

        var result = AttributedString()
        var charIndex = 0

        for char in strippedContent {
            let progress = Double(charIndex) / Double(max(1, contentLength))
            let color = interpolateGradient(colors: rainbowColors, progress: progress)

            var attrChar = AttributedString(String(char))
            attrChar.foregroundColor = color
            result.append(attrChar)
            charIndex += 1
        }

        let tagContent = String(remaining[remaining.index(after: remaining.startIndex)..<tagEndIndex])
        let startOffset = text.distance(from: text.startIndex, to: startIndex)
        let totalLength = "<".count + tagContent.count + ">".count + rainbowContent.count + "</rainbow>".count
        let endIndex = text.index(text.startIndex, offsetBy: startOffset + totalLength, limitedBy: text.endIndex) ?? text.endIndex

        return (result, endIndex)
    }

    /// Parse a color string (hex or named) to RGB values
    private static func parseColorToRGB(_ colorStr: String) -> (r: Double, g: Double, b: Double)? {
        var hex = colorStr.trimmingCharacters(in: .whitespaces)

        // Check for hex color
        if hex.hasPrefix("#") {
            hex = String(hex.dropFirst())
        }

        // Check if it's a valid 6-char hex
        if hex.count == 6, hex.allSatisfy({ $0.isHexDigit }) {
            return hexToRGB(hex)
        }

        // Check for named color
        if let namedHex = namedColors[hex.lowercased()] {
            return hexToRGB(namedHex)
        }

        return nil
    }

    /// Convert hex string to RGB tuple
    private static func hexToRGB(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        guard hex.count == 6 else { return nil }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return (r, g, b)
    }

    /// Interpolate between gradient colors
    private static func interpolateGradient(colors: [(r: Double, g: Double, b: Double)], progress: Double) -> Color {
        guard colors.count >= 2 else {
            return colors.isEmpty ? .white : Color(red: colors[0].r, green: colors[0].g, blue: colors[0].b)
        }

        let clampedProgress = max(0, min(1, progress))
        let segments = colors.count - 1
        let segmentProgress = clampedProgress * Double(segments)
        let segmentIndex = min(Int(segmentProgress), segments - 1)
        let localProgress = segmentProgress - Double(segmentIndex)

        let startColor = colors[segmentIndex]
        let endColor = colors[segmentIndex + 1]

        let r = startColor.r + (endColor.r - startColor.r) * localProgress
        let g = startColor.g + (endColor.g - startColor.g) * localProgress
        let b = startColor.b + (endColor.b - startColor.b) * localProgress

        return Color(red: r, green: g, blue: b)
    }

    /// Strip color codes from text for length calculation
    private static func stripColorCodes(_ text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            // Skip § or & color codes
            if (char == "§" || char == "&") {
                let nextIndex = text.index(after: index)
                if nextIndex < text.endIndex {
                    let codeChar = text[nextIndex].lowercased().first!
                    // Check for extended hex format §x§R§R§G§G§B§B
                    if codeChar == "x" {
                        var skipIndex = text.index(after: nextIndex)
                        for _ in 0..<6 {
                            guard skipIndex < text.endIndex else { break }
                            if text[skipIndex] == "§" || text[skipIndex] == "&" {
                                skipIndex = text.index(after: skipIndex)
                                if skipIndex < text.endIndex {
                                    skipIndex = text.index(after: skipIndex)
                                }
                            } else {
                                break
                            }
                        }
                        index = skipIndex
                        continue
                    }
                    // Skip regular color/format code
                    index = text.index(after: nextIndex)
                    continue
                }
            }

            // Skip MiniMessage tags
            if char == "<" {
                if let closeIndex = text[index...].firstIndex(of: ">") {
                    index = text.index(after: closeIndex)
                    continue
                }
            }

            result.append(char)
            index = text.index(after: index)
        }

        return result
    }

    /// Formatting state
    struct Formatting {
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrikethrough = false
    }

    /// Parse a single character with color codes
    private static func parseCharacter(_ text: String, at index: String.Index, defaultColor: Color, currentColor: Color, formatting: Formatting) -> (AttributedString, String.Index) {
        var attrChar = AttributedString(String(text[index]))
        attrChar.foregroundColor = currentColor
        return (attrChar, text.index(after: index))
    }

    /// Standard parsing for Minecraft color codes (§ and & formats)
    private static func parseStandard(_ text: String, defaultColor: Color) -> AttributedString {
        var result = AttributedString()
        var currentColor = defaultColor
        var isBold = false
        var isItalic = false
        var isUnderline = false
        var isStrikethrough = false

        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]

            // Check for § color code
            if char == "§" || char == "&" {
                let nextIndex = text.index(after: index)
                guard nextIndex < text.endIndex else {
                    var attrChar = AttributedString(String(char))
                    attrChar.foregroundColor = currentColor
                    result.append(attrChar)
                    index = nextIndex
                    continue
                }

                let codeChar = text[nextIndex].lowercased().first!

                // Check for hex color: §x§R§R§G§G§B§B
                if codeChar == "x" {
                    if let hexColor = parseExtendedHex(text, from: nextIndex) {
                        currentColor = hexColor.color
                        index = hexColor.endIndex
                        continue
                    }
                }

                // Check for standard color code
                if let hex = colorCodes[codeChar] {
                    currentColor = Color(hex: hex)
                    index = text.index(after: nextIndex)
                    continue
                }

                // Check for format codes
                if formatCodes.contains(codeChar) {
                    switch codeChar {
                    case "l": isBold = true
                    case "o": isItalic = true
                    case "n": isUnderline = true
                    case "m": isStrikethrough = true
                    case "r":
                        currentColor = defaultColor
                        isBold = false
                        isItalic = false
                        isUnderline = false
                        isStrikethrough = false
                    default: break
                    }
                    index = text.index(after: nextIndex)
                    continue
                }
            }

            // Check for &#RRGGBB format
            if char == "&" {
                if let hexResult = parseAmpersandHex(text, from: index) {
                    currentColor = hexResult.color
                    index = hexResult.endIndex
                    continue
                }
            }

            // Check for <#RRGGBB> or <color:#RRGGBB> format
            if char == "<" {
                if let tagResult = parseMiniMessageTag(text, from: index) {
                    if let color = tagResult.color {
                        currentColor = color
                    } else if tagResult.isReset {
                        currentColor = defaultColor
                        isBold = false
                        isItalic = false
                        isUnderline = false
                        isStrikethrough = false
                    }
                    index = tagResult.endIndex
                    continue
                }
            }

            // Regular character - apply current formatting
            var attrChar = AttributedString(String(char))
            attrChar.foregroundColor = currentColor

            if isBold {
                attrChar.font = .custom("Menlo-Bold", size: 12)
            }
            if isItalic {
                attrChar.font = .custom("Menlo-Italic", size: 12)
            }
            if isUnderline {
                attrChar.underlineStyle = .single
            }
            if isStrikethrough {
                attrChar.strikethroughStyle = .single
            }

            result.append(attrChar)
            index = text.index(after: index)
        }

        return result
    }

    /// Parse §x§R§R§G§G§B§B format (extended hex)
    private static func parseExtendedHex(_ text: String, from startIndex: String.Index) -> (color: Color, endIndex: String.Index)? {
        // Need 12 more characters after 'x': §R§R§G§G§B§B
        var hexChars = ""
        var currentIndex = text.index(after: startIndex) // Skip 'x'

        for _ in 0..<6 {
            guard currentIndex < text.endIndex else { return nil }
            let char = text[currentIndex]
            guard char == "§" || char == "&" else { return nil }

            currentIndex = text.index(after: currentIndex)
            guard currentIndex < text.endIndex else { return nil }

            hexChars.append(text[currentIndex])
            currentIndex = text.index(after: currentIndex)
        }

        guard hexChars.count == 6 else { return nil }
        return (Color(hex: hexChars), currentIndex)
    }

    /// Parse &#RRGGBB format
    private static func parseAmpersandHex(_ text: String, from startIndex: String.Index) -> (color: Color, endIndex: String.Index)? {
        let nextIndex = text.index(after: startIndex)
        guard nextIndex < text.endIndex, text[nextIndex] == "#" else { return nil }

        var hexStart = text.index(after: nextIndex)
        var hexChars = ""

        for _ in 0..<6 {
            guard hexStart < text.endIndex else { return nil }
            let char = text[hexStart]
            guard char.isHexDigit else { return nil }
            hexChars.append(char)
            hexStart = text.index(after: hexStart)
        }

        return (Color(hex: hexChars), hexStart)
    }

    /// Parse MiniMessage tags: <#RRGGBB>, <color:#RRGGBB>, </color>, <reset>
    private static func parseMiniMessageTag(_ text: String, from startIndex: String.Index) -> (color: Color?, isReset: Bool, endIndex: String.Index)? {
        guard let closeIndex = text[startIndex...].firstIndex(of: ">") else { return nil }

        let tagContent = String(text[text.index(after: startIndex)..<closeIndex])
        let endIndex = text.index(after: closeIndex)

        // Check for <#RRGGBB>
        if tagContent.hasPrefix("#") && tagContent.count == 7 {
            let hex = String(tagContent.dropFirst())
            return (Color(hex: hex), false, endIndex)
        }

        // Check for <color:#RRGGBB> or <colour:#RRGGBB>
        if tagContent.hasPrefix("color:#") || tagContent.hasPrefix("colour:#") {
            let hex = String(tagContent.split(separator: ":").last ?? "")
            if hex.count == 6 || (hex.hasPrefix("#") && hex.count == 7) {
                let cleanHex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
                return (Color(hex: cleanHex), false, endIndex)
            }
        }

        // Check for color names
        if tagContent.hasPrefix("color:") || tagContent.hasPrefix("colour:") {
            let colorName = String(tagContent.split(separator: ":").last ?? "").lowercased()
            if let hex = namedColors[colorName] {
                return (Color(hex: hex), false, endIndex)
            }
        }

        // Check for just a named color like <red>, <blue>, etc.
        if let hex = namedColors[tagContent.lowercased()] {
            return (Color(hex: hex), false, endIndex)
        }

        // Check for closing tags or reset
        if tagContent.hasPrefix("/") || tagContent == "reset" || tagContent == "r" {
            return (nil, true, endIndex)
        }

        // Not a recognized tag, return nil to output the < character
        return nil
    }
}

// MARK: - Command History

struct CommandHistory: Codable {
    var commands: [String]
    var maxSize: Int

    init(maxSize: Int = 100) {
        self.commands = []
        self.maxSize = maxSize
    }

    mutating func add(_ command: String) {
        // Don't add duplicates of the last command
        if commands.last != command {
            commands.append(command)
            // Trim to max size
            if commands.count > maxSize {
                commands.removeFirst(commands.count - maxSize)
            }
        }
    }
}
