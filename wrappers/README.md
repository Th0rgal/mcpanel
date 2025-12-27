# MCPanel Server Setup Guide

This guide explains how to configure your Minecraft server for use with MCPanel's console feature.

## Console Modes

MCPanel supports several console connection modes. Choose based on your server setup:

| Mode | Recommendation | Native Scrollback | Truecolor | Dependencies |
|------|----------------|-------------------|-----------|--------------|
| **MCWrap** | ⭐ Recommended | ✅ | ✅ | None |
| **Tmux** | Good alternative | ❌* | ✅** | tmux |
| **Screen** | Legacy | ❌* | ❌ | screen |
| **Direct** | Testing only | ✅ | ✅ | None |
| **Log Tail** | Read-only | N/A | N/A | None |

\* tmux/screen use alternate screen buffer which disables terminal scrollback
\** tmux requires specific configuration for truecolor

---

## Option 1: MCWrap (Recommended)

MCWrap is a lightweight bash wrapper that provides the best experience:
- Native scrollback (scroll with trackpad/mouse wheel)
- Full 24-bit truecolor support
- Session persistence (server survives SSH disconnects)
- No dependencies beyond bash

### Installation

```bash
# Copy mcwrap to your server
scp mcwrap user@server:/usr/local/bin/
ssh user@server chmod +x /usr/local/bin/mcwrap
```

### Manual Usage

```bash
# Start server
mcwrap start /path/to/minecraft

# Attach to console (interactive)
mcwrap attach /path/to/minecraft

# Send a command
mcwrap send /path/to/minecraft "say Hello!"

# Check status
mcwrap status /path/to/minecraft

# Stop server gracefully
mcwrap stop /path/to/minecraft

# View recent logs
mcwrap log /path/to/minecraft 500
```

### systemd Service

Create `/etc/systemd/system/minecraft.service`:

```ini
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=forking
User=minecraft
WorkingDirectory=/opt/minecraft
ExecStart=/usr/local/bin/mcwrap start /opt/minecraft -Xms4G -Xmx8G -jar server.jar --nogui
ExecStop=/usr/local/bin/mcwrap stop /opt/minecraft
Restart=on-failure
RestartSec=10
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
systemctl daemon-reload
systemctl enable minecraft
systemctl start minecraft
```

### MCPanel Configuration

1. In MCPanel, select your server
2. Go to Settings
3. Set **Console Mode** to **MCWrap**
4. Set **Server Path** to your Minecraft directory (e.g., `/opt/minecraft`)

---

## Option 2: Tmux

Tmux works well if you prefer a standard terminal multiplexer. Requires additional configuration for truecolor.

### Installation

```bash
apt install tmux  # Debian/Ubuntu
yum install tmux  # RHEL/CentOS
```

### Truecolor Configuration

Create `~/.tmux.conf` on your server:

```bash
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",*256col*:Tc"
set -ga terminal-overrides ",xterm-256color:Tc"
```

### systemd Service

Create `/etc/systemd/system/minecraft.service`:

```ini
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=forking
User=minecraft
WorkingDirectory=/opt/minecraft
Environment=TERM=xterm-256color
Environment=COLORTERM=truecolor
ExecStart=/usr/bin/tmux new-session -d -s minecraft /usr/bin/java -Dnet.kyori.ansi.colorLevel=truecolor -Xms4G -Xmx8G -jar server.jar --nogui
ExecStop=/usr/bin/tmux send-keys -t minecraft "stop" Enter
Restart=on-failure
RestartSec=10
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
```

### MCPanel Configuration

1. Set **Console Mode** to **Tmux**
2. Set **Tmux Session** to your session name (e.g., `minecraft`)

### Limitations

- No native scrollback (MCPanel sends tmux copy-mode commands for scrolling)
- Scrolling feels less smooth than mcwrap

---

## Option 3: Screen

GNU Screen is a legacy option. It does **not** support truecolor.

### Installation

```bash
apt install screen  # Debian/Ubuntu
yum install screen  # RHEL/CentOS
```

### systemd Service

```ini
[Unit]
Description=Minecraft Server
After=network.target

[Service]
Type=forking
User=minecraft
WorkingDirectory=/opt/minecraft
ExecStart=/usr/bin/screen -dmS minecraft /usr/bin/java -Xms4G -Xmx8G -jar server.jar --nogui
ExecStop=/usr/bin/screen -S minecraft -X stuff "stop^M"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### MCPanel Configuration

1. Set **Console Mode** to **Screen**
2. Set **Screen Session** to your session name (e.g., `minecraft`)

### Limitations

- No truecolor (16-color maximum)
- No native scrollback
- Less reliable than tmux

---

## Option 4: Log Tail (Read-Only)

Simple log streaming with no interactive input. Use this if you only need to monitor output.

### MCPanel Configuration

1. Set **Console Mode** to **Log Tail**
2. MCPanel will stream `logs/latest.log`

### Limitations

- Read-only (cannot send commands)
- No ANSI colors
- For monitoring only

---

## Option 5: Direct PTY

Direct shell connection without any session wrapper. The server process will terminate when you disconnect.

### When to Use

- Quick testing
- Servers that auto-restart via external process manager

### MCPanel Configuration

1. Set **Console Mode** to **Direct**
2. MCPanel connects directly to a bash shell in your server directory

### Limitations

- No session persistence
- Server stops when MCPanel disconnects

---

## Truecolor Support

For plugins that output rich colors (like Oraxen, custom MOTDs), you need truecolor support.

### Requirements

1. **Console Mode**: MCWrap or Tmux (with config)
2. **Java Flag**: `-Dnet.kyori.ansi.colorLevel=truecolor`
3. **Environment**: `COLORTERM=truecolor`

MCWrap handles all of this automatically. For tmux, add the Java flag to your start command and configure `~/.tmux.conf` as shown above.

---

## Troubleshooting

### "Not running" when attaching with mcwrap

The server isn't started or crashed. Check:
```bash
mcwrap status /path/to/minecraft
mcwrap log /path/to/minecraft 100
```

### No colors in console

1. Verify console mode supports color (MCWrap or Tmux)
2. Check Java flag: `-Dnet.kyori.ansi.colorLevel=truecolor`
3. For tmux, verify `~/.tmux.conf` has the `Tc` terminal override

### Scrolling doesn't work

- **MCWrap**: Native scrollback works automatically
- **Tmux/Screen**: MCPanel sends copy-mode commands; scrolling may feel different
- **Log Tail/Direct**: No scrollback available

### Session already attached (tmux)

Tmux sessions can only have one client in control mode. Either:
1. Detach other clients: `tmux detach -s minecraft`
2. Use mcwrap instead (supports multiple viewers)

---

## mcwrap Command Reference

```
mcwrap - Simple Minecraft server wrapper

Usage: mcwrap <command> <server-dir> [args...]

Commands:
  start <dir> [java-args]   Start server (backgrounded, persists)
  attach <dir> [--raw]      Interactive console (--raw for MCPanel)
  stream <dir> [N]          Output N history lines + follow
  tail <dir>                Follow log (output only)
  send <dir> <command>      Send single command
  status <dir>              Show status
  stop <dir>                Graceful shutdown
  log <dir> [N]             Show last N lines (default: 100)
  list                      List all managed servers

Environment:
  MCWRAP_DIR          State directory (default: ~/.mcwrap)
  MCWRAP_LOG_LINES    Max log lines (default: 50000)
```

---

## How mcwrap Works

```
┌─────────────────────────────────────────────┐
│  mcwrap daemon (persistent)                 │
│                                             │
│  stdin ← named pipe ← mcwrap attach/send    │
│            ↓                                │
│  java -jar server.jar --nogui               │
│            ↓                                │
│  stdout → console.log (with ANSI colors)    │
│              → mcwrap attach (live view)    │
└─────────────────────────────────────────────┘
```

1. The wrapper runs Java in the background with a named pipe for input
2. All output is logged to `~/.mcwrap/<id>/console.log` with colors preserved
3. `attach` shows recent history + follows live output + accepts input
4. `send` writes commands to the input pipe
5. The server keeps running even when no clients are attached

---

## Alternative Wrappers

### mc-wrapper-socat

Advanced version using socat for multi-client support.

**Pros:**
- Multiple clients can connect simultaneously
- Better socket handling

**Cons:**
- Requires `socat` package

```bash
apt install socat
```
