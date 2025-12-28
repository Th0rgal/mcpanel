# MCPanel Bridge Architecture

## Overview

MCPanel Bridge is a lightweight server-side plugin that provides real-time communication between MCPanel (macOS app) and Minecraft servers. It exposes server data via a simple JSON protocol over the existing PTY/console connection (no extra ports needed).

## Design Goals

1. **Zero Configuration** - Works out of the box when dropped into plugins/
2. **Optimal with mcwrap** - Full features when using mcwrap PTY mode
3. **Graceful Degradation** - Works with screen/tmux/log-tail with reduced features
4. **Multi-Platform** - Paper, Spigot, Folia, Velocity, BungeeCord
5. **Real-time Completions** - Leverages Paper's AsyncTabCompleteEvent
6. **Minimal Overhead** - No polling, event-driven architecture

## Communication Protocol

### Transport Layer

MCPanel Bridge communicates via **inline protocol messages** in the console output. This works because:
- mcwrap already captures all PTY output
- No extra ports/sockets needed (firewall-friendly)
- Works through SSH tunnels automatically

### Message Format

```
\x1B]1337;MCPanel:<base64-json>\x07
```

Uses OSC (Operating System Command) escape sequence with iTerm2's custom sequence number (1337). This is:
- Invisible to normal terminal display
- Easily parsed by MCPanel's terminal emulator
- Won't corrupt log files (mcwrap filters OSC sequences)

### JSON Protocol

```typescript
// MCPanel -> Server (via stdin)
interface MCPanelRequest {
  id: string;           // Request ID for response matching
  type: "complete" | "commands" | "players" | "status" | "plugins";
  payload?: any;
}

// Server -> MCPanel (via stdout OSC)
interface MCPanelResponse {
  id: string;           // Matches request ID
  type: string;         // Response type
  payload: any;         // Response data
}

// Server -> MCPanel (unsolicited events)
interface MCPanelEvent {
  event: "player_join" | "player_leave" | "command_registered" | "plugin_loaded" | "server_ready";
  payload: any;
}
```

### Message Types

#### 1. Tab Completion (Real-time)

```json
// Request (MCPanel types partial command)
{"id":"c1","type":"complete","payload":{"buffer":"oraxen re"}}

// Response (instant on Paper, polled on Spigot)
{"id":"c1","type":"completions","payload":{
  "completions": [
    {"text":"reload","tooltip":"Reload Oraxen configuration"},
    {"text":"repair","tooltip":"Repair held item"}
  ],
  "isAsync": true
}}
```

#### 2. Command Tree

```json
// Request
{"id":"c2","type":"commands"}

// Response
{"id":"c2","type":"command_tree","payload":{
  "commands": {
    "oraxen": {
      "description": "Oraxen main command",
      "aliases": ["o", "oxn"],
      "children": {
        "reload": {"description":"Reload configuration"},
        "give": {"description":"Give custom item","children":{...}}
      }
    }
  }
}}
```

#### 3. Player List

```json
{"id":"c3","type":"players"}

{"id":"c3","type":"player_list","payload":{
  "count": 5,
  "max": 100,
  "players": [
    {"name":"Th0rgal","uuid":"...","world":"world","health":20,"op":true}
  ]
}}
```

#### 4. Plugin List (Enhanced)

```json
{"id":"c4","type":"plugins"}

{"id":"c4","type":"plugin_list","payload":{
  "plugins": [
    {"name":"Oraxen","version":"2.0.0","enabled":true,"authors":["Th0rgal"],"commands":["oraxen","o"]},
    {"name":"Essentials","version":"2.21.0","enabled":true,"authors":["EssentialsX Team"],"commands":["essentials","eco","pay"]}
  ]
}}
```

#### 5. Server Status

```json
{"id":"c5","type":"status"}

{"id":"c5","type":"server_status","payload":{
  "version": "1.21.1",
  "software": "Paper",
  "softwareVersion": "build 123",
  "onlinePlayers": 5,
  "maxPlayers": 100,
  "tps": [20.0, 19.98, 19.95],
  "mspt": 45.2,
  "memory": {"used": 4096, "max": 8192},
  "worlds": [
    {"name":"world","players":3,"entities":1234,"chunks":567}
  ]
}}
```

## Platform Implementations

### Paper (Full Features)

```java
// AsyncTabCompleteEvent for real-time completions
@EventHandler
public void onAsyncTabComplete(AsyncTabCompleteEvent event) {
    if (event.getSender() instanceof ConsoleCommandSender) {
        // MCPanel is typing in console
        String buffer = event.getBuffer();
        if (pendingCompletionRequest != null) {
            List<Completion> completions = event.completions();
            sendResponse(pendingCompletionRequest, completions);
        }
    }
}

// Access Brigadier tree directly
CommandNode<CommandSourceStack> root = server.getCommands().getDispatcher().getRoot();
```

### Spigot (Fallback)

```java
// No AsyncTabCompleteEvent - use TabCompleteEvent (sync, limited)
@EventHandler
public void onTabComplete(TabCompleteEvent event) {
    // Less efficient but works
}

// No direct Brigadier access - parse plugin.yml for commands
```

### Velocity (Proxy)

```java
// Different command API
@Subscribe
public void onCommandExecute(CommandExecuteEvent event) {
    // Handle completion requests
}

// Velocity-specific player info
```

### BungeeCord (Legacy Proxy)

```java
// Minimal support - player list and basic commands
```

## Module Structure

```
mcpanel-bridge/
├── build.gradle.kts              # Root build configuration
├── settings.gradle.kts           # Module definitions
│
├── mcpanel-bridge-core/          # Shared protocol & utilities
│   └── src/main/java/
│       └── dev/th0rgal/mcpanel/bridge/
│           ├── protocol/
│           │   ├── MCPanelMessage.java
│           │   ├── MCPanelRequest.java
│           │   ├── MCPanelResponse.java
│           │   └── MCPanelEvent.java
│           ├── handler/
│           │   ├── RequestHandler.java
│           │   └── CompletionHandler.java
│           └── util/
│               ├── OSCEncoder.java
│               └── BrigadierExporter.java
│
├── mcpanel-bridge-bukkit/        # Paper & Spigot
│   └── src/main/java/
│       └── dev/th0rgal/mcpanel/bridge/bukkit/
│           ├── MCPanelBridgePlugin.java
│           ├── paper/
│           │   └── PaperCompletionHandler.java
│           └── spigot/
│               └── SpigotCompletionHandler.java
│
├── mcpanel-bridge-velocity/      # Velocity proxy
│   └── src/main/java/
│       └── dev/th0rgal/mcpanel/bridge/velocity/
│           └── MCPanelBridgeVelocity.java
│
└── mcpanel-bridge-bungee/        # BungeeCord (minimal)
    └── src/main/java/
        └── dev/th0rgal/mcpanel/bridge/bungee/
            └── MCPanelBridgeBungee.java
```

## MCPanel Integration

### Detecting Bridge

MCPanel detects the bridge by looking for the handshake event on PTY connect:

```json
{"event":"mcpanel_bridge_ready","payload":{"version":"1.0.0","platform":"paper","features":["async_complete","brigadier","rich_tooltips"]}}
```

### Fallback Behavior

| Feature | With Bridge | Without Bridge |
|---------|-------------|----------------|
| Command suggestions | Real-time Brigadier tree | plugin.yml parsing |
| Tab completion | Async with tooltips | Send Tab key, parse response |
| Player list | Rich data (health, world) | RCON `list` command |
| TPS/Performance | Real-time MSPT | None |
| Plugin list | Full metadata | File system scan |

### Backward Compatibility

MCPanel continues to work without the bridge using existing methods:
1. Parse plugin.yml from JAR files
2. Send Tab key for server-side completion
3. Use RCON for basic commands
4. Tail log files

The bridge just makes everything faster and more feature-rich.

## mcwrap Integration

When mcwrap is used, the bridge can:
1. Write OSC messages directly to stdout (captured by mcwrap)
2. Read requests via a control socket (optional, for out-of-band messages)

### Extended mcwrap Protocol (Optional)

```rust
// In mcwrap, add optional control channel
enum McwrapMessage {
    PtyData(Vec<u8>),           // Normal PTY I/O
    McPanelRequest(String),      // JSON request from MCPanel
    McPanelResponse(String),     // JSON response from bridge
}
```

This allows cleaner separation but the inline OSC approach works without mcwrap changes.

## Security Considerations

1. **No Network Exposure** - Bridge uses console I/O, not sockets
2. **Console Access = Full Control** - If someone has console access, they already have full server access
3. **No Authentication** - Relies on SSH/PTY authentication
4. **Rate Limiting** - Debounce completion requests (100ms)

## Performance

1. **Async Completions** - Paper's AsyncTabCompleteEvent runs off main thread
2. **Cached Command Tree** - Rebuilt only on plugin reload
3. **Lazy Loading** - Player/world data only fetched on request
4. **Minimal Serialization** - Use Gson with type adapters

## Future Extensions

1. **File Transfer** - Base64-encoded file chunks for plugin upload
2. **Remote REPL** - Execute Kotlin/Groovy scripts
3. **Metrics Stream** - Real-time TPS/memory graphs
4. **Log Filtering** - Server-side log level filtering
