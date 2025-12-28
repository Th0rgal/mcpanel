# Debugging Command Completion in MCPanel

This guide explains how to debug and test the command completion feature in MCPanel.

## Overview

The command completion feature involves several components:
1. **MCPanelBridge plugin** - Generates `commands.json` on the server
2. **MCPanelBridgeService** - Fetches and parses commands via SFTP/RCON
3. **ServerManager** - Maintains `commandTree` for each server
4. **CommandInputBar** - Shows autocomplete suggestions in the UI

## Debug Tools

### 1. Debug Logger

The `DebugLogger` writes detailed logs to a file for post-mortem debugging.

**Enable verbose logging:**
```bash
# Set environment variable before launching MCPanel
export MCPANEL_DEBUG=1
./MCPanel.app/Contents/MacOS/MCPanel
```

**Log file location:**
```
~/Library/Application Support/MCPanel/debug/mcpanel-debug-<timestamp>.log
```

**Log categories:**
- `SYS` - System/lifecycle events
- `BRIDGE` - Bridge plugin detection
- `CMDS` - Command tree fetching/parsing
- `SSH` - SSH command execution
- `UI` - UI autocomplete requests
- `PTY` - PTY/terminal events

### 2. CLI Test Tool

A standalone Swift script for testing SSH connection and command fetching.

**Location:** `tools/test-command-completion.swift`

**Usage:**

```bash
# Test SSH connection
swift tools/test-command-completion.swift test-ssh myserver.com minecraft \
    --identity ~/.ssh/id_ed25519

# Fetch commands.json from server
swift tools/test-command-completion.swift fetch-commands myserver.com minecraft \
    /home/minecraft/server --identity ~/.ssh/id_ed25519

# Parse a local commands.json
swift tools/test-command-completion.swift parse-json ./commands.json

# Test autocomplete interactively
swift tools/test-command-completion.swift test-autocomplete ./commands.json "ora"
```

### 3. Debug Panel (In-App)

A debug panel accessible via keyboard shortcut to inspect command completion state.

**How to access:**
- Press `Cmd+Option+D` to open the debug panel
- Or add a menu item using `DebugMenuItem` view

**What it shows:**
- Server connection info
- Bridge detection status
- Command tree statistics
- Live autocomplete testing
- Raw JSON inspection
- Log file quick access

## Common Issues & Debugging Steps

### Issue: No autocomplete suggestions

**Step 1: Check if commands.json exists on server**
```bash
swift tools/test-command-completion.swift test-ssh myserver.com user --identity ~/.ssh/key
# Look for "Found commands.json" in output
```

**Step 2: Check if bridge plugin is installed**
```bash
# Look for MCPanelBridge*.jar in the plugins folder
ssh user@server "ls -la /path/to/server/plugins/ | grep -i mcpanel"
```

**Step 3: Check command tree in app**
1. Open the debug panel (`Cmd+Option+D`)
2. Check "Command Tree" section
3. Verify "Root Commands" count > 0

**Step 4: Check logs**
```bash
cat ~/Library/Application\ Support/MCPanel/debug/mcpanel-debug-*.log | grep -i "commands"
```

### Issue: Bridge not detected

**Step 1: Check console output for bridge ready message**
The bridge outputs `[MCPanelBridge] Bridge ready` when loaded.

**Step 2: Verify plugin is enabled**
```bash
ssh user@server "cat /path/to/server/plugins/MCPanelBridge/config.yml"
```

**Step 3: Check for plugin errors**
```bash
ssh user@server "grep -i mcpanel /path/to/server/logs/latest.log"
```

### Issue: Commands not updating after reload

**Step 1: Check if commands.json was regenerated**
```bash
ssh user@server "ls -la /path/to/server/plugins/MCPanelBridge/commands.json"
# Check timestamp
```

**Step 2: Force refresh in app**
1. Open debug panel
2. Click "Fetch Now" button
3. Check if command count increases

**Step 3: Check for SFTP errors in logs**
```bash
grep "SFTP\|commands.json" ~/Library/Application\ Support/MCPanel/debug/*.log
```

## Testing Workflow

### Local Testing (without server)

1. Create/edit `tools/sample-commands.json` with test commands
2. Run the parse command to verify structure:
   ```bash
   swift tools/test-command-completion.swift parse-json tools/sample-commands.json
   ```
3. Test autocomplete:
   ```bash
   swift tools/test-command-completion.swift test-autocomplete tools/sample-commands.json "game"
   ```

### Integration Testing (with server)

1. Ensure MCPanelBridge plugin is installed and enabled
2. Restart server to generate fresh commands.json
3. In MCPanel:
   - Connect to the server
   - Open debug panel (`Cmd+Option+D`)
   - Click "Fetch Now"
   - Test autocomplete with various prefixes

### Adding Debug Points

To add custom debug logging in code:

```swift
import Foundation

// Get the shared logger
let logger = DebugLogger.shared

// Log with category
logger.log("Custom message", category: .commands)

// Verbose logging (only when MCPANEL_DEBUG=1)
logger.log("Detailed info", category: .commands, verbose: true)

// Use convenience methods
logger.logCommandTreeFetch(serverPath: path, method: "SFTP")
logger.logCommandTreeResult(commandCount: 42, source: "Bridge")
logger.logCommandTreeError(error, source: "RCON")
logger.logAutocomplete(prefix: "ora", resultCount: 5)
```

## Files Reference

| File | Purpose |
|------|---------|
| `mcpanel/Services/DebugLogger.swift` | Centralized debug logging |
| `mcpanel/Services/MCPanelBridgeService.swift` | Bridge communication |
| `mcpanel/Services/ServerManager.swift` | Command tree management |
| `mcpanel/Views/Components/CommandInputBar.swift` | Autocomplete UI |
| `mcpanel/Views/Components/CommandDebugPanel.swift` | Debug panel UI |
| `tools/test-command-completion.swift` | CLI debug tool |
| `tools/sample-commands.json` | Test data for CLI tool |

## Expected Log Output (Healthy)

When working correctly, you should see logs like:
```
[HH:MM:SS.mmm] [CMDS] Fetching commands.json via SFTP from: /path/plugins/MCPanelBridge/commands.json
[HH:MM:SS.mmm] [CMDS] Read 15234 bytes from commands.json
[HH:MM:SS.mmm] [CMDS] Loaded 142 commands from SFTP/commands.json
[HH:MM:SS.mmm] [UI] Autocomplete for 'ora': 1 suggestions
```

## Troubleshooting Matrix

| Symptom | Check | Solution |
|---------|-------|----------|
| No suggestions | commands.json exists? | Install MCPanelBridge |
| Empty command tree | SFTP works? | Check SSH key permissions |
| Old commands shown | File timestamp | Reload server, fetch again |
| Bridge not detected | Plugin enabled? | Check plugin status |
| Suggestions slow | Network? | Check SSH latency |
