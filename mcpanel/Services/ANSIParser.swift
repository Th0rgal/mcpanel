//
//  ANSIParser.swift
//  MCPanel
//
//  State machine-based ANSI/VT100 escape sequence parser
//  Based on: https://vt100.net/emu/dec_ansi_parser
//           https://github.com/haberman/vtparse
//

import SwiftUI

/// A proper state machine parser for ANSI/VT100 escape sequences
/// Converts terminal output to AttributedString with colors
final class ANSIParser {
    
    // MARK: - Types
    
    enum State {
        case ground
        case escape
        case escapeIntermediate
        case csiEntry
        case csiParam
        case csiIntermediate
        case csiIgnore
        case oscString
        case dcsEntry
        case dcsParam
        case dcsIntermediate
        case dcsPassthrough
        case dcsIgnore
        case sosPmApcString
    }
    
    /// Raw RGB color representation for serialization
    struct RawColor: Equatable {
        var r: Int
        var g: Int
        var b: Int
        var isDefault: Bool

        static let defaultForeground = RawColor(r: 255, g: 255, b: 255, isDefault: true)
        static let defaultBackground = RawColor(r: 0, g: 0, b: 0, isDefault: true)

        var asColor: Color {
            Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
        }
    }

    struct TextStyle {
        var foreground: Color = .white
        var background: Color? = nil
        var bold: Bool = false
        var dim: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var blink: Bool = false
        var inverse: Bool = false
        var hidden: Bool = false
        var strikethrough: Bool = false

        // Raw RGB values for serialization
        var rawForeground: RawColor = .defaultForeground
        var rawBackground: RawColor = .defaultBackground

        mutating func reset() {
            foreground = .white
            background = nil
            bold = false
            dim = false
            italic = false
            underline = false
            blink = false
            inverse = false
            hidden = false
            strikethrough = false
            rawForeground = .defaultForeground
            rawBackground = .defaultBackground
        }

        var effectiveForeground: Color {
            let base = inverse ? (background ?? Color(white: 0.1)) : foreground
            return dim ? base.opacity(0.6) : base
        }

        var effectiveBackground: Color? {
            inverse ? foreground : background
        }
    }
    
    // MARK: - State
    
    private var state: State = .ground
    private var intermediates: [UInt8] = []
    private var params: [Int] = []
    private var currentParam: Int = 0
    private var hasCurrentParam: Bool = false
    
    private var style = TextStyle()
    private var result = AttributedString()
    private var currentText = ""
    
    // MARK: - Public API
    
    /// Parse ANSI text and return AttributedString with colors
    static func parse(_ text: String) -> AttributedString {
        let parser = ANSIParser()
        return parser.process(text)
    }
    
    /// Process input text and return attributed string
    func process(_ text: String) -> AttributedString {
        result = AttributedString()
        currentText = ""

        for scalar in text.unicodeScalars {
            // For unicode characters beyond Latin-1 (> 255), append directly as printable
            if scalar.value > 255 {
                // Treat as printable character (emoji, CJK, etc.)
                currentText.append(Character(scalar))
            } else {
                let byte = UInt8(scalar.value)
                processByte(byte, char: Character(scalar))
            }
        }

        // Flush any remaining text
        flushText()

        return result
    }
    
    // MARK: - State Machine
    
    private func processByte(_ byte: UInt8, char: Character) {
        // Handle "anywhere" transitions first
        switch byte {
        case 0x18, 0x1A: // CAN, SUB - cancel sequence
            flushText()
            clear()
            state = .ground
            return
        case 0x1B: // ESC - start escape sequence
            flushText()
            clear()
            state = .escape
            return
        case 0x9B: // CSI (8-bit)
            flushText()
            clear()
            state = .csiEntry
            return
        case 0x9D: // OSC (8-bit)
            flushText()
            clear()
            state = .oscString
            return
        case 0x90: // DCS (8-bit)
            flushText()
            clear()
            state = .dcsEntry
            return
        case 0x98, 0x9E, 0x9F: // SOS, PM, APC (8-bit)
            flushText()
            clear()
            state = .sosPmApcString
            return
        case 0x9C: // ST (String Terminator)
            flushText()
            state = .ground
            return
        default:
            break
        }
        
        // State-specific handling
        switch state {
        case .ground:
            handleGround(byte, char: char)
        case .escape:
            handleEscape(byte)
        case .escapeIntermediate:
            handleEscapeIntermediate(byte)
        case .csiEntry:
            handleCsiEntry(byte)
        case .csiParam:
            handleCsiParam(byte)
        case .csiIntermediate:
            handleCsiIntermediate(byte)
        case .csiIgnore:
            handleCsiIgnore(byte)
        case .oscString, .sosPmApcString:
            handleStringState(byte)
        case .dcsEntry:
            handleDcsEntry(byte)
        case .dcsParam:
            handleDcsParam(byte)
        case .dcsIntermediate:
            handleDcsIntermediate(byte)
        case .dcsPassthrough:
            handleDcsPassthrough(byte)
        case .dcsIgnore:
            handleDcsIgnore(byte)
        }
    }
    
    // MARK: - State Handlers
    
    private func handleGround(_ byte: UInt8, char: Character) {
        switch byte {
        case 0x00...0x1F:
            // C0 controls - execute (mostly ignore for display)
            if byte == 0x0A { // LF
                currentText.append("\n")
            } else if byte == 0x0D { // CR
                // Ignore CR (usually paired with LF)
            } else if byte == 0x09 { // TAB
                currentText.append("\t")
            }
            // Other C0 controls ignored
        case 0x20...0x7E:
            // Printable ASCII
            currentText.append(char)
        case 0x7F:
            // DEL - ignore
            break
        case 0xA0...0xFF:
            // Printable high bytes (treat like GL)
            currentText.append(char)
        default:
            break
        }
    }
    
    private func handleEscape(_ byte: UInt8) {
        switch byte {
        case 0x00...0x1F:
            // C0 controls - execute
            break
        case 0x20...0x2F:
            // Intermediate - collect and transition
            intermediates.append(byte)
            state = .escapeIntermediate
        case 0x30...0x4F, 0x51...0x57, 0x59, 0x5A, 0x5C, 0x60...0x7E:
            // Final characters - dispatch escape sequence
            dispatchEscape(byte)
            state = .ground
        case 0x5B: // '[' - CSI
            clear()
            state = .csiEntry
        case 0x5D: // ']' - OSC
            clear()
            state = .oscString
        case 0x50: // 'P' - DCS
            clear()
            state = .dcsEntry
        case 0x58, 0x5E, 0x5F: // 'X', '^', '_' - SOS, PM, APC
            clear()
            state = .sosPmApcString
        case 0x7F:
            // DEL - ignore
            break
        default:
            state = .ground
        }
    }
    
    private func handleEscapeIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x00...0x1F:
            // C0 controls - execute
            break
        case 0x20...0x2F:
            // More intermediates
            intermediates.append(byte)
        case 0x30...0x7E:
            // Final - dispatch
            dispatchEscape(byte)
            state = .ground
        case 0x7F:
            // DEL - ignore
            break
        default:
            state = .ground
        }
    }
    
    private func handleCsiEntry(_ byte: UInt8) {
        switch byte {
        case 0x00...0x1F:
            // C0 controls - execute
            break
        case 0x20...0x2F:
            // Intermediate
            intermediates.append(byte)
            state = .csiIntermediate
        case 0x30...0x39: // '0'-'9'
            currentParam = Int(byte - 0x30)
            hasCurrentParam = true
            state = .csiParam
        case 0x3A: // ':' - subparameter (ignore sequence)
            state = .csiIgnore
        case 0x3B: // ';' - parameter separator
            params.append(0) // Default value
            state = .csiParam
        case 0x3C...0x3F: // '<', '=', '>', '?' - private marker
            intermediates.append(byte)
            state = .csiParam
        case 0x40...0x7E:
            // Final - dispatch
            dispatchCsi(byte)
            state = .ground
        case 0x7F:
            // DEL - ignore
            break
        default:
            state = .ground
        }
    }
    
    private func handleCsiParam(_ byte: UInt8) {
        switch byte {
        case 0x00...0x1F:
            // C0 controls - execute
            break
        case 0x20...0x2F:
            // Intermediate
            if hasCurrentParam {
                params.append(currentParam)
                currentParam = 0
                hasCurrentParam = false
            }
            intermediates.append(byte)
            state = .csiIntermediate
        case 0x30...0x39: // '0'-'9'
            currentParam = currentParam * 10 + Int(byte - 0x30)
            hasCurrentParam = true
        case 0x3A: // ':' - subparameter
            state = .csiIgnore
        case 0x3B: // ';' - parameter separator
            params.append(hasCurrentParam ? currentParam : 0)
            currentParam = 0
            hasCurrentParam = false
        case 0x3C...0x3F: // Private markers in wrong position
            state = .csiIgnore
        case 0x40...0x7E:
            // Final - dispatch
            if hasCurrentParam {
                params.append(currentParam)
            }
            dispatchCsi(byte)
            state = .ground
        case 0x7F:
            // DEL - ignore
            break
        default:
            state = .ground
        }
    }
    
    private func handleCsiIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x00...0x1F:
            // C0 controls - execute
            break
        case 0x20...0x2F:
            // More intermediates
            intermediates.append(byte)
        case 0x30...0x3F:
            // Parameters after intermediate - error
            state = .csiIgnore
        case 0x40...0x7E:
            // Final - dispatch
            dispatchCsi(byte)
            state = .ground
        case 0x7F:
            // DEL - ignore
            break
        default:
            state = .ground
        }
    }
    
    private func handleCsiIgnore(_ byte: UInt8) {
        switch byte {
        case 0x00...0x1F:
            // C0 controls - execute
            break
        case 0x20...0x3F:
            // Ignore
            break
        case 0x40...0x7E:
            // Final - transition to ground (no dispatch)
            state = .ground
        case 0x7F:
            // DEL - ignore
            break
        default:
            state = .ground
        }
    }
    
    private func handleStringState(_ byte: UInt8) {
        // OSC, SOS, PM, APC strings - ignore until ST
        switch byte {
        case 0x07: // BEL - alternative terminator for OSC
            state = .ground
        case 0x00...0x1F:
            // Ignore most C0
            break
        default:
            // Ignore string content
            break
        }
    }
    
    private func handleDcsEntry(_ byte: UInt8) {
        // Similar to CSI entry but for device control strings
        switch byte {
        case 0x20...0x2F:
            intermediates.append(byte)
            state = .dcsIntermediate
        case 0x30...0x39, 0x3B:
            state = .dcsParam
        case 0x3C...0x3F:
            intermediates.append(byte)
            state = .dcsParam
        case 0x40...0x7E:
            state = .dcsPassthrough
        default:
            break
        }
    }
    
    private func handleDcsParam(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39, 0x3B:
            break // Collect params
        case 0x20...0x2F:
            state = .dcsIntermediate
        case 0x40...0x7E:
            state = .dcsPassthrough
        case 0x3A, 0x3C...0x3F:
            state = .dcsIgnore
        default:
            break
        }
    }
    
    private func handleDcsIntermediate(_ byte: UInt8) {
        switch byte {
        case 0x20...0x2F:
            break // More intermediates
        case 0x40...0x7E:
            state = .dcsPassthrough
        case 0x30...0x3F:
            state = .dcsIgnore
        default:
            break
        }
    }
    
    private func handleDcsPassthrough(_ byte: UInt8) {
        // Ignore DCS content
    }
    
    private func handleDcsIgnore(_ byte: UInt8) {
        // Ignore until ST
    }
    
    // MARK: - Dispatch
    
    private func dispatchEscape(_ final: UInt8) {
        // Most escape sequences we don't care about for display
        // Could handle things like ESC 7 (save cursor) if needed
    }
    
    private func dispatchCsi(_ final: UInt8) {
        // Check for private marker
        let isPrivate = !intermediates.isEmpty && intermediates[0] >= 0x3C && intermediates[0] <= 0x3F
        
        switch final {
        case 0x6D: // 'm' - SGR (Select Graphic Rendition)
            if !isPrivate {
                handleSGR()
            }
        default:
            // Other CSI sequences (cursor movement, etc.) - ignore for display
            break
        }
    }
    
    // MARK: - SGR (Colors and Styles)
    
    private func handleSGR() {
        // If no parameters, treat as reset
        if params.isEmpty {
            style.reset()
            return
        }
        
        var i = 0
        while i < params.count {
            let code = params[i]
            
            switch code {
            case 0:
                style.reset()
            case 1:
                style.bold = true
            case 2:
                style.dim = true
            case 3:
                style.italic = true
            case 4:
                style.underline = true
            case 5, 6:
                style.blink = true
            case 7:
                style.inverse = true
            case 8:
                style.hidden = true
            case 9:
                style.strikethrough = true
            case 22:
                style.bold = false
                style.dim = false
            case 23:
                style.italic = false
            case 24:
                style.underline = false
            case 25:
                style.blink = false
            case 27:
                style.inverse = false
            case 28:
                style.hidden = false
            case 29:
                style.strikethrough = false
                
            // Foreground colors (30-37)
            case 30: setForeground(r: 51, g: 51, b: 51)
            case 31: setForeground(r: 240, g: 84, b: 79)
            case 32: setForeground(r: 84, g: 219, b: 110)
            case 33: setForeground(r: 250, g: 189, b: 64)
            case 34: setForeground(r: 102, g: 145, b: 237)
            case 35: setForeground(r: 212, g: 107, b: 199)
            case 36: setForeground(r: 77, g: 209, b: 222)
            case 37: setForeground(r: 230, g: 230, b: 230)
            case 39: resetForeground()
                
            // Background colors (40-47)
            case 40: setBackground(r: 26, g: 26, b: 26)
            case 41: setBackground(r: 153, g: 38, b: 38)
            case 42: setBackground(r: 38, g: 128, b: 51)
            case 43: setBackground(r: 153, g: 115, b: 26)
            case 44: setBackground(r: 38, g: 64, b: 140)
            case 45: setBackground(r: 128, g: 51, b: 115)
            case 46: setBackground(r: 26, g: 115, b: 128)
            case 47: setBackground(r: 179, g: 179, b: 179)
            case 49: resetBackground()

            // Bright foreground (90-97)
            case 90: setForeground(r: 128, g: 128, b: 128)
            case 91: setForeground(r: 255, g: 115, b: 115)
            case 92: setForeground(r: 115, g: 255, b: 140)
            case 93: setForeground(r: 255, g: 230, b: 115)
            case 94: setForeground(r: 140, g: 179, b: 255)
            case 95: setForeground(r: 255, g: 140, b: 242)
            case 96: setForeground(r: 115, g: 242, b: 255)
            case 97: setForeground(r: 255, g: 255, b: 255)

            // Bright background (100-107)
            case 100: setBackground(r: 102, g: 102, b: 102)
            case 101: setBackground(r: 204, g: 77, b: 77)
            case 102: setBackground(r: 77, g: 179, b: 89)
            case 103: setBackground(r: 204, g: 166, b: 51)
            case 104: setBackground(r: 89, g: 115, b: 191)
            case 105: setBackground(r: 179, g: 102, b: 166)
            case 106: setBackground(r: 64, g: 166, b: 179)
            case 107: setBackground(r: 217, g: 217, b: 217)

            // 256 color mode (38;5;n or 48;5;n)
            case 38:
                if i + 2 < params.count && params[i + 1] == 5 {
                    let rgb = color256RGB(params[i + 2])
                    setForeground(r: rgb.r, g: rgb.g, b: rgb.b)
                    i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    // True color: 38;2;r;g;b
                    setForeground(r: params[i + 2], g: params[i + 3], b: params[i + 4])
                    i += 4
                }
            case 48:
                if i + 2 < params.count && params[i + 1] == 5 {
                    let rgb = color256RGB(params[i + 2])
                    setBackground(r: rgb.r, g: rgb.g, b: rgb.b)
                    i += 2
                } else if i + 4 < params.count && params[i + 1] == 2 {
                    // True color: 48;2;r;g;b
                    setBackground(r: params[i + 2], g: params[i + 3], b: params[i + 4])
                    i += 4
                }
                
            default:
                break
            }
            
            i += 1
        }
    }
    
    // MARK: - Helpers
    
    private func clear() {
        intermediates.removeAll()
        params.removeAll()
        currentParam = 0
        hasCurrentParam = false
    }
    
    private func flushText() {
        guard !currentText.isEmpty else { return }
        
        var attr = AttributedString(currentText)
        attr.foregroundColor = style.effectiveForeground
        attr.font = .system(size: 13, weight: style.bold ? .bold : .regular, design: .monospaced)
        
        if let bg = style.effectiveBackground {
            attr.backgroundColor = bg
        }
        if style.underline {
            attr.underlineStyle = .single
        }
        if style.strikethrough {
            attr.strikethroughStyle = .single
        }
        
        result.append(attr)
        currentText = ""
    }
    
    // MARK: - Color Helpers

    private func setForeground(r: Int, g: Int, b: Int) {
        style.foreground = Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
        style.rawForeground = RawColor(r: r, g: g, b: b, isDefault: false)
    }

    private func resetForeground() {
        style.foreground = .white
        style.rawForeground = .defaultForeground
    }

    private func setBackground(r: Int, g: Int, b: Int) {
        style.background = Color(red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0)
        style.rawBackground = RawColor(r: r, g: g, b: b, isDefault: false)
    }

    private func resetBackground() {
        style.background = nil
        style.rawBackground = .defaultBackground
    }

    /// Get 256-color as RGB tuple
    private func color256RGB(_ index: Int) -> (r: Int, g: Int, b: Int) {
        guard index >= 0 && index < 256 else { return (255, 255, 255) }

        if index < 16 {
            // Standard 16 colors
            let colors: [(r: Int, g: Int, b: Int)] = [
                (26, 26, 26),     // 0: Black
                (204, 51, 51),    // 1: Red
                (51, 204, 77),    // 2: Green
                (204, 179, 51),   // 3: Yellow
                (77, 102, 230),   // 4: Blue
                (204, 77, 179),   // 5: Magenta
                (51, 179, 204),   // 6: Cyan
                (217, 217, 217),  // 7: White
                (102, 102, 102),  // 8: Bright Black
                (255, 102, 102),  // 9: Bright Red
                (102, 255, 128),  // 10: Bright Green
                (255, 242, 102),  // 11: Bright Yellow
                (128, 153, 255),  // 12: Bright Blue
                (255, 128, 230),  // 13: Bright Magenta
                (102, 242, 255),  // 14: Bright Cyan
                (255, 255, 255),  // 15: Bright White
            ]
            return colors[index]
        } else if index < 232 {
            // 216 color cube (6x6x6)
            let n = index - 16
            let b = n % 6
            let g = (n / 6) % 6
            let r = n / 36
            return (
                r: r == 0 ? 0 : r * 40 + 55,
                g: g == 0 ? 0 : g * 40 + 55,
                b: b == 0 ? 0 : b * 40 + 55
            )
        } else {
            // Grayscale (24 shades)
            let gray = (index - 232) * 10 + 8
            return (r: gray, g: gray, b: gray)
        }
    }

    private func color256(_ index: Int) -> Color {
        let rgb = color256RGB(index)
        return Color(red: Double(rgb.r) / 255.0, green: Double(rgb.g) / 255.0, blue: Double(rgb.b) / 255.0)
    }

    // MARK: - State Export

    /// Export current style state as an ANSI escape sequence
    /// This allows warming up the parser on hidden lines and then
    /// applying the resulting state to the first visible line
    func currentStateAsANSI() -> String {
        var parts: [String] = []

        // Reset first, then set active attributes
        parts.append("0")

        // Bold/dim
        if style.bold { parts.append("1") }
        if style.dim { parts.append("2") }
        if style.italic { parts.append("3") }
        if style.underline { parts.append("4") }
        if style.blink { parts.append("5") }
        if style.inverse { parts.append("7") }
        if style.hidden { parts.append("8") }
        if style.strikethrough { parts.append("9") }

        // Foreground color (truecolor)
        if !style.rawForeground.isDefault {
            let fg = style.rawForeground
            parts.append("38;2;\(fg.r);\(fg.g);\(fg.b)")
        }

        // Background color (truecolor)
        if !style.rawBackground.isDefault {
            let bg = style.rawBackground
            parts.append("48;2;\(bg.r);\(bg.g);\(bg.b)")
        }

        // If only reset, return just the reset sequence
        if parts == ["0"] {
            return "\u{1B}[0m"
        }

        return "\u{1B}[\(parts.joined(separator: ";"))m"
    }

    /// Check if the style differs from default (white foreground, no background, no attributes)
    var hasNonDefaultState: Bool {
        return !style.rawForeground.isDefault
            || !style.rawBackground.isDefault
            || style.bold
            || style.dim
            || style.italic
            || style.underline
            || style.blink
            || style.inverse
            || style.hidden
            || style.strikethrough
    }
}
