<p align="center">
  <img src="output.png" alt="MCPanel" width="200">
</p>

<h1 align="center">MCPanel</h1>

<p align="center">
  <strong>Open source</strong> macOS Minecraft server control panel. Beautiful. Minimal. Native.
</p>

<p align="center">
  <a href="#building">Build it yourself</a> · <a href="#features">Features</a>
</p>

---

## What is this?

MCPanel is a native macOS application for managing remote Minecraft servers. It provides a clean, minimal interface with a liquid glass aesthetic that feels right at home on macOS.

This project is **fully open source**. You can clone it, build it, modify it, and use it however you like.

- **SSH & RCON** support for remote server management
- **Live console** with colored output and command history
- **Plugin management** with enable/disable toggling
- **File browser** for server files
- **Server version management** via mcjarfiles.com API

## Features

| Feature | Description |
|---------|-------------|
| **Multi-Server** | Manage multiple remote Minecraft servers |
| **Live Console** | Real-time log streaming with ANSI color support |
| **RCON Integration** | Send commands directly to the server |
| **Plugin Manager** | Enable/disable plugins, view metadata |
| **File Browser** | Native file explorer for server files |
| **Version Manager** | Download and update server JARs |

## Requirements

- macOS 14.0+ (Sonoma)
- SSH access to your Minecraft server
- RCON enabled on the server (optional but recommended)

## Building

### Quick Build

```bash
./build-app.sh
```

This will:
1. Build the app in release mode
2. Create the `MCPanel.app` bundle
3. Launch the app automatically

### Clean Rebuild

If you need to rebuild from scratch:

```bash
swift package clean && rm -rf .build MCPanel.app && ./build-app.sh
```

## Configuration

Create a `.secrets.json` file in the project root with your server credentials:

```json
{
  "servers": {
    "my_server": {
      "name": "My Server",
      "ssh": {
        "host": "your.server.ip",
        "port": 22,
        "user": "root",
        "identity_file": "~/.ssh/id_rsa"
      },
      "paths": {
        "root_dir": "/path/to/minecraft",
        "plugins_dir": "/path/to/minecraft/plugins",
        "jar_path": "/path/to/minecraft/server.jar"
      },
      "rcon": {
        "host": "127.0.0.1",
        "port": 25575,
        "password": "your_rcon_password"
      }
    }
  }
}
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `⌘N` | Add new server |
| `⌘⌫` | Remove selected server |
| `⌘R` | Restart server |
| `⌘.` | Stop server |
| `⌘⏎` | Send console command |
| `⌘1-9` | Quick switch servers |

## Project Structure

```
mcpanel/
├── mcpanel/
│   ├── Models/           # Server, Plugin, ConsoleMessage
│   ├── Services/         # SSH, RCON, FileTransfer, Persistence
│   ├── Views/            # SwiftUI views
│   └── Assets.xcassets/  # App icons and colors
├── build-app.sh          # Build script
└── Package.swift         # Swift Package Manager config
```

## Data Storage

Server configurations are stored in:
```
~/Library/Application Support/MCPanel/
```

SSH credentials are stored in macOS Keychain.
