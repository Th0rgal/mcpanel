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
