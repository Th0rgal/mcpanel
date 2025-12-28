#!/usr/bin/env swift
//
//  test-command-completion.swift
//  MCPanel Debug Tool
//
//  CLI tool to test and debug the command completion feature.
//  Run with: swift tools/test-command-completion.swift --help
//
//  Usage:
//    swift tools/test-command-completion.swift test-ssh <host> <user> [--identity <path>] [--port <port>]
//    swift tools/test-command-completion.swift fetch-commands <host> <user> <server-path> [--identity <path>]
//    swift tools/test-command-completion.swift test-autocomplete <commands.json> <prefix>
//    swift tools/test-command-completion.swift parse-json <commands.json>
//

import Foundation

// MARK: - Color Output

enum ANSIColor: String {
    case reset = "\u{001B}[0m"
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case cyan = "\u{001B}[36m"
    case gray = "\u{001B}[90m"
}

func colored(_ text: String, _ color: ANSIColor) -> String {
    return "\(color.rawValue)\(text)\(ANSIColor.reset.rawValue)"
}

func printSuccess(_ message: String) {
    print(colored("✓ \(message)", .green))
}

func printError(_ message: String) {
    print(colored("✗ \(message)", .red))
}

func printInfo(_ message: String) {
    print(colored("→ \(message)", .blue))
}

func printWarning(_ message: String) {
    print(colored("⚠ \(message)", .yellow))
}

func printHeader(_ message: String) {
    print("\n" + colored("=== \(message) ===", .cyan) + "\n")
}

// MARK: - SSH Execution

func runSSH(host: String, user: String, port: Int = 22, identityFile: String?, command: String, timeout: TimeInterval = 30) -> (output: String, error: String, exitCode: Int32) {
    var args: [String] = []

    if let identity = identityFile, !identity.isEmpty {
        let expandedPath = NSString(string: identity).expandingTildeInPath
        args.append(contentsOf: ["-i", expandedPath])
    }

    args.append(contentsOf: [
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR"
    ])

    if port != 22 {
        args.append(contentsOf: ["-p", String(port)])
    }

    args.append("\(user)@\(host)")
    args.append(command)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    process.arguments = args

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        return ("", "Failed to run SSH: \(error)", -1)
    }

    // Wait with timeout
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }

    if process.isRunning {
        process.terminate()
        return ("", "SSH command timed out", -1)
    }

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    let output = String(data: outputData, encoding: .utf8) ?? ""
    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

    return (output, errorOutput, process.terminationStatus)
}

// MARK: - Command Tree Parsing

struct CommandNode: Codable {
    let type: String?
    let executable: Bool?
    let children: [String: CommandNode]?
}

struct CommandTree: Codable {
    let commands: [String: CommandNode]
}

func parseCommandTree(from jsonString: String) -> CommandTree? {
    guard let data = jsonString.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(CommandTree.self, from: data)
}

func getCompletions(tree: CommandTree, prefix: String) -> [String] {
    let lowercasePrefix = prefix.lowercased()
    var completions: [String] = []

    for (name, _) in tree.commands {
        if name.lowercased().hasPrefix(lowercasePrefix) {
            completions.append(name)
        }
    }

    return completions.sorted()
}

// MARK: - Commands

func printUsage() {
    print("""
    MCPanel Command Completion Debug Tool

    \(colored("USAGE:", .cyan))
      swift tools/test-command-completion.swift <command> [options]

    \(colored("COMMANDS:", .cyan))
      test-ssh <host> <user>           Test SSH connection
          --identity <path>            SSH identity file (optional)
          --port <port>                SSH port (default: 22)

      fetch-commands <host> <user> <server-path>
          Fetch commands.json from server via SSH
          --identity <path>            SSH identity file (optional)
          --port <port>                SSH port (default: 22)

      test-autocomplete <commands.json> <prefix>
          Test autocomplete with a local commands.json file

      parse-json <commands.json>
          Parse and display a commands.json file

    \(colored("EXAMPLES:", .cyan))
      # Test SSH connection
      swift tools/test-command-completion.swift test-ssh myserver.com minecraft --identity ~/.ssh/id_ed25519

      # Fetch commands from server
      swift tools/test-command-completion.swift fetch-commands myserver.com minecraft /home/minecraft/server

      # Test autocomplete locally
      swift tools/test-command-completion.swift test-autocomplete ./commands.json "ora"

    \(colored("ENVIRONMENT:", .cyan))
      MCPANEL_SSH_HOST          Default SSH host
      MCPANEL_SSH_USER          Default SSH user
      MCPANEL_SSH_IDENTITY      Default SSH identity file
      MCPANEL_SERVER_PATH       Default server path
    """)
}

func commandTestSSH(args: [String]) {
    guard args.count >= 2 else {
        printError("Usage: test-ssh <host> <user> [--identity <path>] [--port <port>]")
        return
    }

    let host = args[0]
    let user = args[1]
    var identityFile: String?
    var port = 22

    var i = 2
    while i < args.count {
        if args[i] == "--identity" && i + 1 < args.count {
            identityFile = args[i + 1]
            i += 2
        } else if args[i] == "--port" && i + 1 < args.count {
            port = Int(args[i + 1]) ?? 22
            i += 2
        } else {
            i += 1
        }
    }

    printHeader("Testing SSH Connection")
    printInfo("Host: \(user)@\(host):\(port)")
    if let identity = identityFile {
        printInfo("Identity: \(identity)")
    }

    // Test 1: Basic connection
    printInfo("Testing basic connection...")
    let (output1, error1, code1) = runSSH(host: host, user: user, port: port, identityFile: identityFile, command: "echo 'SSH_OK'")

    if code1 == 0 && output1.contains("SSH_OK") {
        printSuccess("SSH connection successful")
    } else {
        printError("SSH connection failed: \(error1)")
        return
    }

    // Test 2: Check for commands.json in common locations
    printInfo("Checking for commands.json in common locations...")

    let searchPaths = [
        "~/server/plugins/MCPanelBridge/commands.json",
        "/home/minecraft/server/plugins/MCPanelBridge/commands.json",
        "/opt/minecraft/plugins/MCPanelBridge/commands.json"
    ]

    for path in searchPaths {
        let (output, _, code) = runSSH(host: host, user: user, port: port, identityFile: identityFile, command: "test -f \(path) && echo 'FOUND' || echo 'NOT_FOUND'")
        if output.contains("FOUND") {
            printSuccess("Found commands.json at: \(path)")
        } else {
            print(colored("  Not found: \(path)", .gray))
        }
    }

    // Test 3: Check for bridge plugin
    printInfo("Checking for MCPanelBridge plugin...")
    let (output3, _, _) = runSSH(host: host, user: user, port: port, identityFile: identityFile, command: "find ~/ -name 'MCPanelBridge*.jar' -type f 2>/dev/null | head -5")
    if !output3.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        printSuccess("Found bridge plugin(s):")
        for line in output3.components(separatedBy: .newlines) where !line.isEmpty {
            print("    \(line)")
        }
    } else {
        printWarning("MCPanelBridge plugin not found")
    }
}

func commandFetchCommands(args: [String]) {
    guard args.count >= 3 else {
        printError("Usage: fetch-commands <host> <user> <server-path> [--identity <path>] [--port <port>]")
        return
    }

    let host = args[0]
    let user = args[1]
    let serverPath = args[2]
    var identityFile: String?
    var port = 22

    var i = 3
    while i < args.count {
        if args[i] == "--identity" && i + 1 < args.count {
            identityFile = args[i + 1]
            i += 2
        } else if args[i] == "--port" && i + 1 < args.count {
            port = Int(args[i + 1]) ?? 22
            i += 2
        } else {
            i += 1
        }
    }

    printHeader("Fetching commands.json")
    printInfo("Server: \(user)@\(host):\(port)")
    printInfo("Path: \(serverPath)")

    let commandsPath = "\(serverPath)/plugins/MCPanelBridge/commands.json"
    printInfo("Looking for: \(commandsPath)")

    let (output, error, code) = runSSH(host: host, user: user, port: port, identityFile: identityFile, command: "cat '\(commandsPath)' 2>/dev/null")

    if code != 0 || output.isEmpty {
        printError("Failed to fetch commands.json")
        printError("Error: \(error)")

        // Try to diagnose
        printInfo("Diagnosing...")
        let (lsOutput, _, _) = runSSH(host: host, user: user, port: port, identityFile: identityFile, command: "ls -la '\(serverPath)/plugins/' 2>/dev/null | head -20")
        print("\nPlugins directory:")
        print(lsOutput)
        return
    }

    printSuccess("Fetched commands.json (\(output.count) bytes)")

    // Parse and display
    if let tree = parseCommandTree(from: output) {
        printSuccess("Parsed \(tree.commands.count) root commands")
        print("\nRoot commands:")
        for name in tree.commands.keys.sorted().prefix(30) {
            print("  - \(name)")
        }
        if tree.commands.count > 30 {
            print("  ... and \(tree.commands.count - 30) more")
        }

        // Save to local file for further testing
        let localPath = "commands-\(host).json"
        try? output.write(toFile: localPath, atomically: true, encoding: .utf8)
        printInfo("Saved to: \(localPath)")
    } else {
        printError("Failed to parse commands.json")
        print("\nRaw content (first 1000 chars):")
        print(String(output.prefix(1000)))
    }
}

func commandTestAutocomplete(args: [String]) {
    guard args.count >= 2 else {
        printError("Usage: test-autocomplete <commands.json> <prefix>")
        return
    }

    let jsonPath = args[0]
    let prefix = args[1]

    printHeader("Testing Autocomplete")
    printInfo("File: \(jsonPath)")
    printInfo("Prefix: '\(prefix)'")

    guard let jsonString = try? String(contentsOfFile: jsonPath, encoding: .utf8) else {
        printError("Failed to read file: \(jsonPath)")
        return
    }

    guard let tree = parseCommandTree(from: jsonString) else {
        printError("Failed to parse commands.json")
        return
    }

    let completions = getCompletions(tree: tree, prefix: prefix)

    if completions.isEmpty {
        printWarning("No completions found for prefix '\(prefix)'")
    } else {
        printSuccess("Found \(completions.count) completions:")
        for name in completions.prefix(20) {
            print("  - \(name)")
        }
        if completions.count > 20 {
            print("  ... and \(completions.count - 20) more")
        }
    }

    // Interactive mode
    print("\n" + colored("Interactive mode (type prefix, Ctrl+C to exit):", .cyan))
    while let line = readLine() {
        let results = getCompletions(tree: tree, prefix: line)
        if results.isEmpty {
            print("  (no matches)")
        } else {
            print("  \(results.prefix(10).joined(separator: ", "))\(results.count > 10 ? " ..." : "")")
        }
    }
}

func commandParseJSON(args: [String]) {
    guard args.count >= 1 else {
        printError("Usage: parse-json <commands.json>")
        return
    }

    let jsonPath = args[0]

    printHeader("Parsing commands.json")
    printInfo("File: \(jsonPath)")

    guard let jsonString = try? String(contentsOfFile: jsonPath, encoding: .utf8) else {
        printError("Failed to read file: \(jsonPath)")
        return
    }

    printInfo("File size: \(jsonString.count) bytes")

    guard let tree = parseCommandTree(from: jsonString) else {
        printError("Failed to parse as CommandTree")

        // Try to parse as generic JSON
        if let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            printInfo("Parsed as generic JSON")
            print("Top-level keys: \(json.keys.sorted())")
        } else {
            printError("Not valid JSON")
            print("\nFirst 500 characters:")
            print(String(jsonString.prefix(500)))
        }
        return
    }

    printSuccess("Successfully parsed commands.json")
    print("\nStatistics:")
    print("  Root commands: \(tree.commands.count)")

    var withChildren = 0
    var maxDepth = 0

    func measureDepth(_ node: CommandNode, depth: Int) -> Int {
        guard let children = node.children, !children.isEmpty else { return depth }
        var max = depth
        for (_, child) in children {
            let childDepth = measureDepth(child, depth: depth + 1)
            if childDepth > max { max = childDepth }
        }
        return max
    }

    for (_, node) in tree.commands {
        if let children = node.children, !children.isEmpty {
            withChildren += 1
            let depth = measureDepth(node, depth: 1)
            if depth > maxDepth { maxDepth = depth }
        }
    }

    print("  Commands with subcommands: \(withChildren)")
    print("  Max command depth: \(maxDepth)")

    print("\nAll root commands:")
    for name in tree.commands.keys.sorted() {
        let node = tree.commands[name]!
        let childCount = node.children?.count ?? 0
        if childCount > 0 {
            print("  \(name) (\(childCount) subcommands)")
        } else {
            print("  \(name)")
        }
    }
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args[0] == "--help" || args[0] == "-h" {
    printUsage()
    exit(0)
}

let command = args[0]
let commandArgs = Array(args.dropFirst())

switch command {
case "test-ssh":
    commandTestSSH(args: commandArgs)
case "fetch-commands":
    commandFetchCommands(args: commandArgs)
case "test-autocomplete":
    commandTestAutocomplete(args: commandArgs)
case "parse-json":
    commandParseJSON(args: commandArgs)
default:
    printError("Unknown command: \(command)")
    printUsage()
    exit(1)
}
