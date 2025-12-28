import Foundation

struct CommandTreePayload: Codable {
    let commands: [String: CommandNode]

    struct CommandNode: Codable {
        let description: String?
        let aliases: [String]?
        let permission: String?
        let usage: String?
        let children: [String: CommandNode]?
        let type: String?
        let required: Bool?
        let examples: [String]?

        var isArgument: Bool {
            type != nil && type != "literal"
        }
    }
}

// Test 1: Load local file
print("=== TEST 1: Load from local file ===")
let path = "/tmp/commands.json"
let data = try! Data(contentsOf: URL(fileURLWithPath: path))

do {
    let payload = try JSONDecoder().decode(CommandTreePayload.self, from: data)
    print("Successfully parsed \(payload.commands.count) commands")

    // List all commands starting with 'o'
    let oCommands = payload.commands.keys.filter { $0.lowercased().hasPrefix("o") }.sorted()
    print("\nCommands starting with 'o': \(oCommands.count)")
    for cmd in oCommands {
        print("  - \(cmd)")
    }
} catch {
    print("Parse error: \(error)")
}

// Test 2: Simulate SSH cat (convert output to Data like the app does)
print("\n=== TEST 2: Simulate SSH cat output ===")
if let stringOutput = String(data: data, encoding: .utf8) {
    print("String output length: \(stringOutput.count)")

    // This is what readFile does - convert string back to Data
    if let reconvertedData = stringOutput.data(using: .utf8) {
        print("Reconverted data length: \(reconvertedData.count)")

        do {
            let payload = try JSONDecoder().decode(CommandTreePayload.self, from: reconvertedData)
            print("Successfully parsed \(payload.commands.count) commands from reconverted data")

            let oCommands = payload.commands.keys.filter { $0.lowercased().hasPrefix("o") }.sorted()
            print("Commands starting with 'o': \(oCommands)")
        } catch {
            print("Parse error after reconversion: \(error)")
        }
    }
}

// Test 3: Check if there's any BOM or hidden chars
print("\n=== TEST 3: Check for hidden characters ===")
let firstBytes = [UInt8](data.prefix(10))
print("First 10 bytes: \(firstBytes)")
print("Expected for '{': \([UInt8]("{".utf8))")
