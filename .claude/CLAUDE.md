# MCPanel

Native macOS application for managing remote Minecraft servers. Beautiful. Minimal. Native.

## Tech Stack

- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Platform**: macOS 14.0+ (Sonoma)
- **Build**: Swift Package Manager + Xcode project
- **Networking**: URLSession, SSH (via NIO SSH or libssh2)

## Build Commands

```bash
# Quick build and run
./build-app.sh

# Clean rebuild
swift package clean && rm -rf .build MCPanel.app && ./build-app.sh

# Build with Xcode
open MCPanel.xcodeproj
```

## Project Structure

```
MCPanel/
├── MCPanelApp.swift            # App entry, window config, traffic lights
├── Models/
│   ├── Server.swift            # Server connection model (SSH, RCON)
│   ├── Plugin.swift            # Plugin model (.jar, enabled/disabled state)
│   ├── ServerConfig.swift      # Server configuration/persistence
│   └── ConsoleMessage.swift    # Console log entry model
├── Services/
│   ├── ServerManager.swift     # Central state manager for all servers
│   ├── SSHService.swift        # SSH connection and command execution
│   ├── RCONService.swift       # RCON protocol for server commands
│   ├── FileTransferService.swift # SFTP for file upload/download
│   ├── MCJarService.swift      # mcjarfiles.com API integration
│   └── PersistenceService.swift # JSON save/load for server configs
├── Views/
│   ├── ContentView.swift       # Main layout with floating sidebar
│   ├── SidebarView.swift       # Server list navigation
│   ├── ServerDetailView.swift  # Server controls, console, status
│   ├── ConsoleView.swift       # Live console output + command input
│   ├── PluginsView.swift       # Plugin list with enable/disable toggle
│   ├── FileBrowserView.swift   # Native file explorer for server files
│   ├── ServerConfigView.swift  # Server connection settings
│   ├── VersionManagerView.swift # Download/update server versions
│   └── Components/             # Reusable UI components
└── Assets.xcassets/            # App icons and colors
```

## Core Features

### 1. Multi-Server Management
- Add and configure multiple remote Minecraft servers
- Each server has SSH credentials, RCON port, and server path
- Quick status overview (online/offline, player count, memory)

### 2. Server Control
- **Start/Stop/Restart** via SSH commands
- **RCON integration** for in-game commands
- **Real-time console** with log streaming (tail -f)
- **Command input** with history

### 3. Plugin Management
- List all plugins in the `plugins/` folder
- **Enable/Disable** by renaming `.jar` ↔ `.jar.disabled`
- Drag-and-drop upload new plugins
- View plugin.yml metadata

### 4. File Browser
- Native macOS-style file explorer
- Browse server directory (world folders, configs, logs)
- **Drag-and-drop** files into any folder
- Download files to local machine
- Delete/rename files

### 5. Version Management
- Fetch available versions from mcjarfiles.com API
- Download new server JARs
- Easy server JAR updates

## External APIs

### mcjarfiles.com API (no auth required)

```
Base URL: https://mcjarfiles.com/api

# List all versions for a server type
GET /get-versions/{type}/{variant}
# Types: vanilla, servers, modded, bedrock, proxies
# Variants: release, snapshot, paper, purpur, fabric, forge, velocity

# Download a specific JAR
GET /get-jar/{type}/{variant}/{version}

# Get latest version
GET /get-latest-jar/{type}/{variant}

# Get version metadata
GET /get-version-info/{type}/{variant}/{version}
```

## Design Principles

1. **Native First** — Use system APIs, materials, and behaviors
2. **Liquid Glass Aesthetic** — Translucent materials that sample desktop wallpaper
3. **Minimalism with Purpose** — Show only what's necessary
4. **Real-time Feedback** — Live console, instant status updates
5. **Secure by Default** — SSH keys preferred, credentials in Keychain

## Key Patterns

### Window Configuration
```swift
window.titlebarAppearsTransparent = true
window.titleVisibility = .hidden
window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
window.isMovableByWindowBackground = true
```

### SSH Connection
```swift
// Use NIO SSH or libssh2 wrapper
// Store credentials in macOS Keychain
// Support both password and key-based auth
```

### RCON Protocol
```swift
// Minecraft RCON packet structure:
// [4 bytes: length][4 bytes: request ID][4 bytes: type][payload][2 bytes: padding]
// Types: 3 = login, 2 = command, 0 = response
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `⌘N` | Add new server |
| `⌘⌫` | Remove selected server |
| `⌘R` | Restart server |
| `⌘.` | Stop server |
| `⌘⏎` | Send console command |
| `⌘⌥S` | Toggle sidebar |
| `⌘1-9` | Quick switch servers |

## Data Storage

Server configurations stored in: `~/Library/Application Support/MCPanel/`

SSH credentials stored in macOS Keychain.

## Console Modes & Truecolor Support

MCPanel supports multiple console connection modes:

| Mode | Description | Truecolor Support |
|------|-------------|-------------------|
| **Tmux** | Attach to tmux session (recommended) | ✅ Full 24-bit RGB |
| **Screen** | Attach to screen session | ⚠️ 16-color only |
| **Direct** | Direct PTY shell | Depends on setup |
| **Log Tail** | Traditional `tail -f` | N/A (no ANSI) |

### Recommended Server Setup for Truecolor

For full truecolor (24-bit RGB) console output with plugins like Oraxen, use **tmux** instead of screen:

**1. Create `~/.tmux.conf` on the server:**
```bash
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
set -ga terminal-overrides ",xterm-256color:Tc"
```

**2. Create a systemd service using tmux:**
```ini
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=forking
User=minecraft
WorkingDirectory=/path/to/server
Environment=TERM=xterm-256color
Environment=COLORTERM=truecolor
ExecStart=/usr/bin/tmux new-session -d -s minecraft /usr/bin/java -Dnet.kyori.ansi.colorLevel=truecolor -Xms8G -Xmx12G -jar paper.jar --nogui
ExecStop=/usr/bin/tmux send-keys -t minecraft "stop" Enter
Restart=on-failure
RestartSec=10
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
```

**3. Configure MCPanel** to use "Tmux" console mode in server settings.

### Why Tmux?

- **Screen** ignores `COLORTERM` and always uses 16-color mode regardless of configuration
- **Tmux** with the `Tc` terminal override properly advertises truecolor support to Java/JLine
- The `-Dnet.kyori.ansi.colorLevel=truecolor` JVM flag tells Adventure/Kyori ANSI to use 24-bit colors

## Server Connection Model

```swift
struct Server: Identifiable, Codable {
    let id: UUID
    var name: String
    var host: String
    var sshPort: Int          // Default: 22
    var sshUsername: String
    var authMethod: AuthMethod // .password or .key(path)
    var serverPath: String    // e.g., /home/minecraft/server
    var rconPort: Int?        // Default: 25575
    var rconPassword: String? // Stored in Keychain
    var serverType: ServerType // .paper, .vanilla, .fabric, etc.
    var autoStart: Bool
}
```

## MCPanel Bridge Communication Protocol

**IMPORTANT: Use OSC messages through PTY for all server communication. Do NOT use RCON.**

### Why OSC over RCON?
- RCON is unreliable and spams the console
- OSC messages are embedded in the PTY stream, no extra ports needed
- Works through existing SSH connection
- Supports bi-directional communication (server → app via OSC, app → server via stdin)

### OSC Message Format
Messages are encoded as OSC (Operating System Command) escape sequences that terminals ignore but MCPanel captures:

```
\u{1B}]mcpanel;<base64-json>\u{07}
```

- `\u{1B}]` = OSC start (ESC ])
- `mcpanel;` = MCPanel identifier
- `<base64-json>` = Base64-encoded JSON payload
- `\u{07}` = Bell character (OSC terminator)

### Message Types

**Events (Server → App):**
- `mcpanel_bridge_ready` - Plugin loaded, includes version/platform/features
- `player_join` / `player_leave` - Player events with name/UUID
- `server_ready` - Server finished loading
- `players_update` - Periodic player list broadcast
- `status_update` - TPS, memory, world info
- `registry_update` - Static registries (item IDs, etc.)

**Requests (App → Server via stdin):**
Commands sent to server stdin, responses come back via OSC:
```
mcpanel <base64-request>
```

### Static Data Files
The plugin exports static registries to JSON files on startup/reload:
- `plugins/MCPanelBridge/commands.json` - Brigadier command tree
- `plugins/MCPanelBridge/registries/` - Plugin-specific registries (oraxen_items.json, etc.)

### Implementation Pattern (Swift)
```swift
// In MCPanelBridgeService.swift
func processOutput(_ data: String) -> String {
    guard MCPanelBridgeProtocol.containsMessage(data) else {
        return data
    }
    let messages = MCPanelBridgeProtocol.extractMessages(data)
    for message in messages {
        switch message {
        case .event(let event): handleEvent(event)
        case .response(let response): handleResponse(response)
        }
    }
    return MCPanelBridgeProtocol.filterConsoleOutput(data)
}
```

### Implementation Pattern (Java Plugin)
```java
// Broadcast OSC message to console
public void broadcastEvent(String eventType, Object payload) {
    String json = gson.toJson(new MCPanelEvent(eventType, payload));
    String base64 = Base64.getEncoder().encodeToString(json.getBytes());
    String osc = "\u001B]mcpanel;" + base64 + "\u0007";
    Bukkit.getConsoleSender().sendMessage(osc);
}
```

## Conventions

- Use SF Symbols for icons (16pt)
- Typography: 13pt for lists, 24pt bold for server names
- Corner radius: 12pt for panels
- Sidebar width: 220pt
- Console font: SF Mono 12pt
- Status colors: green (online), red (offline), yellow (starting)
- Always capture objects weakly in notification observers
- Use async/await for SSH operations
- Store sensitive data in Keychain, not UserDefaults
- **Never use RCON** - prefer OSC messages through PTY
