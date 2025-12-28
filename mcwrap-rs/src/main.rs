//! mcwrap - Minecraft server wrapper with PTY support
//!
//! Provides session persistence and proper terminal emulation for
//! interactive console features like tab completion.

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use nix::libc;
use nix::sys::signal::{kill, Signal};
use nix::sys::stat::Mode;
use nix::sys::termios::{cfmakeraw, tcgetattr, tcsetattr, SetArg};
use nix::unistd::Pid;
use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, Read as IoRead, Write as IoWrite};
use std::os::fd::{AsRawFd, BorrowedFd};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tokio::signal::unix::{signal, SignalKind};

mod pty;

/// Minecraft server wrapper with PTY support for interactive console
#[derive(Parser)]
#[command(name = "mcwrap")]
#[command(about = "Minecraft server wrapper with PTY support", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Use basic pipe-based mode (no PTY, no tab completion)
    #[arg(long, global = true)]
    basic: bool,
}

#[derive(Subcommand)]
enum Commands {
    /// Start a Minecraft server
    Start {
        /// Server directory containing the JAR file
        dir: PathBuf,
        /// Java arguments (default: -Xms2G -Xmx4G -jar <jar> --nogui)
        #[arg(trailing_var_arg = true)]
        java_args: Vec<String>,
    },
    /// Attach to a running server console
    Attach {
        /// Server directory
        dir: PathBuf,
        /// Raw mode for MCPanel (no decorations)
        #[arg(long)]
        raw: bool,
    },
    /// Send a command to the server
    Send {
        /// Server directory
        dir: PathBuf,
        /// Command to send
        command: String,
    },
    /// Show server status
    Status {
        /// Server directory
        dir: PathBuf,
    },
    /// Stop the server gracefully
    Stop {
        /// Server directory
        dir: PathBuf,
    },
    /// Show last N lines of console log
    Log {
        /// Server directory
        dir: PathBuf,
        /// Number of lines (default: 100)
        #[arg(default_value = "100")]
        lines: usize,
    },
    /// Follow console log (read-only)
    Tail {
        /// Server directory
        dir: PathBuf,
    },
    /// List all managed servers
    List,
}

/// Server state persisted to disk
#[derive(Serialize, Deserialize)]
struct ServerState {
    pid: i32,
    pty_master: Option<String>, // Path to PTY master (for basic mode: None)
    started_at: u64,
    server_dir: PathBuf,
}

/// Get the wrap directory for a server
fn get_wrap_dir(server_dir: &Path) -> PathBuf {
    let wrap_base = dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".mcwrap");

    // Create unique ID from server path
    let id = format!("{:x}", md5::compute(server_dir.to_string_lossy().as_bytes()));
    let short_id = &id[..12];

    wrap_base.join(short_id)
}

/// Paths for a server's state files
struct ServerPaths {
    wrap_dir: PathBuf,
    state_file: PathBuf,
    log_file: PathBuf,
    socket_path: PathBuf,
}

impl ServerPaths {
    fn new(server_dir: &Path) -> Self {
        let wrap_dir = get_wrap_dir(server_dir);
        Self {
            state_file: wrap_dir.join("state.json"),
            log_file: wrap_dir.join("console.log"),
            socket_path: wrap_dir.join("pty.sock"),
            wrap_dir,
        }
    }

    fn ensure_dir(&self) -> Result<()> {
        fs::create_dir_all(&self.wrap_dir)?;
        Ok(())
    }
}

/// Check if a server is running
fn is_running(paths: &ServerPaths) -> Option<ServerState> {
    let state: ServerState = serde_json::from_reader(File::open(&paths.state_file).ok()?).ok()?;

    // Check if process is still alive
    if kill(Pid::from_raw(state.pid), None).is_ok() {
        Some(state)
    } else {
        // Clean up stale state
        let _ = fs::remove_dir_all(&paths.wrap_dir);
        None
    }
}

/// Find the server JAR file
fn find_jar(server_dir: &Path) -> Result<PathBuf> {
    // Look for common jar names
    let candidates = ["paper.jar", "server.jar", "spigot.jar", "bukkit.jar"];

    for name in candidates {
        let path = server_dir.join(name);
        if path.exists() {
            return Ok(path);
        }
    }

    // Look for any .jar file
    for entry in fs::read_dir(server_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().map_or(false, |e| e == "jar") {
            return Ok(path);
        }
    }

    bail!("No server JAR found in {:?}", server_dir)
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Start { dir, java_args } => cmd_start(&dir, java_args, cli.basic).await,
        Commands::Attach { dir, raw } => cmd_attach(&dir, raw, cli.basic).await,
        Commands::Send { dir, command } => cmd_send(&dir, &command).await,
        Commands::Status { dir } => cmd_status(&dir),
        Commands::Stop { dir } => cmd_stop(&dir).await,
        Commands::Log { dir, lines } => cmd_log(&dir, lines),
        Commands::Tail { dir } => cmd_tail(&dir).await,
        Commands::List => cmd_list(),
    }
}

/// Start the Minecraft server with PTY
async fn cmd_start(server_dir: &Path, java_args: Vec<String>, basic_mode: bool) -> Result<()> {
    let server_dir = server_dir.canonicalize().context("Invalid server directory")?;
    let paths = ServerPaths::new(&server_dir);

    if is_running(&paths).is_some() {
        bail!("Server is already running");
    }

    // Clean up old state
    let _ = fs::remove_dir_all(&paths.wrap_dir);
    paths.ensure_dir()?;

    let jar = find_jar(&server_dir)?;
    let jar_name = jar.file_name().unwrap().to_string_lossy();

    // Build Java command
    let java_args = if java_args.is_empty() {
        vec![
            "-Dnet.kyori.ansi.colorLevel=truecolor".to_string(),
            "-Xms2G".to_string(),
            "-Xmx4G".to_string(),
            "-jar".to_string(),
            jar_name.to_string(),
            "--nogui".to_string(),
        ]
    } else {
        java_args
    };

    println!("Starting server...");
    println!("  Directory: {:?}", server_dir);
    println!("  JAR: {}", jar_name);
    println!("  Mode: {}", if basic_mode { "basic (pipe)" } else { "PTY" });

    if basic_mode {
        start_basic_mode(&server_dir, &paths, &java_args).await
    } else {
        start_pty_mode(&server_dir, &paths, &java_args).await
    }
}

/// Start server in basic pipe mode (no PTY)
async fn start_basic_mode(
    server_dir: &Path,
    paths: &ServerPaths,
    java_args: &[String],
) -> Result<()> {
    // Create FIFO for input
    let input_fifo = paths.wrap_dir.join("input");
    nix::unistd::mkfifo(&input_fifo, Mode::from_bits_truncate(0o600))?;

    // Spawn Java process
    let mut cmd = Command::new("java");
    cmd.args(java_args)
        .current_dir(server_dir)
        .env("TERM", "xterm-256color")
        .env("COLORTERM", "truecolor")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    let mut child = cmd.spawn().context("Failed to start Java")?;
    let pid = child.id() as i32;

    // Save state
    let state = ServerState {
        pid,
        pty_master: None,
        started_at: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs(),
        server_dir: server_dir.to_path_buf(),
    };
    fs::write(&paths.state_file, serde_json::to_string(&state)?)?;

    // Handle output in background
    let log_path = paths.log_file.clone();
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();

    thread::spawn(move || {
        let mut log_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .unwrap();

        let stdout_reader = BufReader::new(stdout);
        for line in stdout_reader.lines().map_while(Result::ok) {
            writeln!(log_file, "{}", line).ok();
        }
    });

    thread::spawn(move || {
        let stderr_reader = BufReader::new(stderr);
        for line in stderr_reader.lines().map_while(Result::ok) {
            eprintln!("{}", line);
        }
    });

    // Handle input from FIFO
    let stdin = child.stdin.take().unwrap();
    let input_fifo_clone = input_fifo.clone();
    thread::spawn(move || {
        let mut stdin = stdin;
        loop {
            if let Ok(fifo) = File::open(&input_fifo_clone) {
                let reader = BufReader::new(fifo);
                for line in reader.lines().map_while(Result::ok) {
                    writeln!(stdin, "{}", line).ok();
                    stdin.flush().ok();
                }
            }
            thread::sleep(Duration::from_millis(100));
        }
    });

    println!("Started (PID {})", pid);
    Ok(())
}

/// Start server with PTY for full terminal emulation
async fn start_pty_mode(
    server_dir: &Path,
    paths: &ServerPaths,
    java_args: &[String],
) -> Result<()> {
    // Fork and create PTY
    let pty_result = pty::spawn_with_pty(server_dir, java_args, &paths.log_file, &paths.socket_path)?;

    // Save state
    let state = ServerState {
        pid: pty_result.child_pid,
        pty_master: Some(paths.socket_path.to_string_lossy().to_string()),
        started_at: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs(),
        server_dir: server_dir.to_path_buf(),
    };
    fs::write(&paths.state_file, serde_json::to_string(&state)?)?;

    println!("Started (PID {})", pty_result.child_pid);
    println!("  Socket: {:?}", paths.socket_path);
    Ok(())
}

/// Attach to server console
async fn cmd_attach(server_dir: &Path, raw: bool, _basic_mode: bool) -> Result<()> {
    let server_dir = server_dir.canonicalize().context("Invalid server directory")?;
    let paths = ServerPaths::new(&server_dir);

    let state = is_running(&paths).context("Server is not running")?;

    if state.pty_master.is_some() {
        // PTY mode - connect to socket
        attach_pty(&paths, raw).await
    } else {
        // Basic mode - tail log + send to FIFO
        attach_basic(&paths, raw).await
    }
}

/// Attach to PTY-based server
async fn attach_pty(paths: &ServerPaths, raw: bool) -> Result<()> {
    let mut stream = UnixStream::connect(&paths.socket_path)
        .await
        .context("Failed to connect to PTY socket")?;

    if !raw {
        println!("Attached to server (Ctrl+C to detach)");
        println!("─────────────────────────────────────────");

        // Show recent history
        if let Ok(content) = fs::read_to_string(&paths.log_file) {
            let lines: Vec<&str> = content.lines().collect();
            let start = lines.len().saturating_sub(30);
            for line in &lines[start..] {
                println!("{}", line);
            }
        }

        println!("─────────────────────────────────────────");
    }

    // Set terminal to raw mode
    let stdin = std::io::stdin();
    let stdin_fd = stdin.as_raw_fd();
    let stdin_borrowed = unsafe { BorrowedFd::borrow_raw(stdin_fd) };
    let original_termios = tcgetattr(&stdin_borrowed).ok();
    if let Some(ref orig) = original_termios {
        let mut raw_termios = orig.clone();
        cfmakeraw(&mut raw_termios);
        tcsetattr(&stdin_borrowed, SetArg::TCSANOW, &raw_termios)?;
    }

    // Setup cleanup
    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();

    // Handle Ctrl+C
    let mut sigint = signal(SignalKind::interrupt())?;
    let r2 = running.clone();
    tokio::spawn(async move {
        sigint.recv().await;
        r2.store(false, Ordering::SeqCst);
    });

    // Bidirectional I/O
    let (mut reader, mut writer) = stream.into_split();

    // Read from PTY, write to stdout
    let r3 = running.clone();
    let stdout_handle = tokio::spawn(async move {
        let mut stdout = tokio::io::stdout();
        let mut buf = [0u8; 4096];
        while r3.load(Ordering::SeqCst) {
            match tokio::time::timeout(Duration::from_millis(100), reader.read(&mut buf)).await {
                Ok(Ok(0)) => break,
                Ok(Ok(n)) => {
                    stdout.write_all(&buf[..n]).await.ok();
                    stdout.flush().await.ok();
                }
                Ok(Err(_)) => break,
                Err(_) => continue, // timeout, check running flag
            }
        }
    });

    // Read from stdin, write to PTY
    let stdin_handle = tokio::spawn(async move {
        let mut stdin = tokio::io::stdin();
        let mut buf = [0u8; 1024];
        while r.load(Ordering::SeqCst) {
            match tokio::time::timeout(Duration::from_millis(100), stdin.read(&mut buf)).await {
                Ok(Ok(0)) => break,
                Ok(Ok(n)) => {
                    writer.write_all(&buf[..n]).await.ok();
                    writer.flush().await.ok();
                }
                Ok(Err(_)) => break,
                Err(_) => continue,
            }
        }
    });

    // Wait for either to finish
    tokio::select! {
        _ = stdout_handle => {},
        _ = stdin_handle => {},
    }

    // Restore terminal
    if let Some(orig) = original_termios {
        tcsetattr(&stdin_borrowed, SetArg::TCSANOW, &orig)?;
    }

    if !raw {
        println!("\nDetached.");
    }

    Ok(())
}

/// Attach to basic pipe-based server
async fn attach_basic(paths: &ServerPaths, raw: bool) -> Result<()> {
    let input_fifo = paths.wrap_dir.join("input");

    if !raw {
        println!("Attached to server (Ctrl+C to detach)");
        println!("─────────────────────────────────────────");

        // Show recent history
        if let Ok(content) = fs::read_to_string(&paths.log_file) {
            let lines: Vec<&str> = content.lines().collect();
            let start = lines.len().saturating_sub(30);
            for line in &lines[start..] {
                println!("{}", line);
            }
        }

        println!("─────────────────────────────────────────");
    }

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();

    // Handle Ctrl+C
    let mut sigint = signal(SignalKind::interrupt())?;
    let r2 = running.clone();
    tokio::spawn(async move {
        sigint.recv().await;
        r2.store(false, Ordering::SeqCst);
    });

    // Tail log file
    let log_path = paths.log_file.clone();
    let r3 = running.clone();
    tokio::spawn(async move {
        let mut last_pos = 0u64;
        while r3.load(Ordering::SeqCst) {
            if let Ok(mut file) = File::open(&log_path) {
                use std::io::Seek;
                let len = file.metadata().map(|m| m.len()).unwrap_or(0);
                if len > last_pos {
                    file.seek(std::io::SeekFrom::Start(last_pos)).ok();
                    let mut buf = String::new();
                    file.read_to_string(&mut buf).ok();
                    print!("{}", buf);
                    std::io::stdout().flush().ok();
                    last_pos = len;
                }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    });

    // Read commands from stdin
    let input = tokio::io::stdin();
    let mut reader = tokio::io::BufReader::new(input);
    let mut line = String::new();

    while r.load(Ordering::SeqCst) {
        line.clear();
        match tokio::time::timeout(Duration::from_millis(100), reader.read_line(&mut line)).await {
            Ok(Ok(0)) => break,
            Ok(Ok(_)) => {
                // Write to FIFO
                if let Ok(mut fifo) = OpenOptions::new().write(true).open(&input_fifo) {
                    write!(fifo, "{}", line).ok();
                }
            }
            Ok(Err(_)) => break,
            Err(_) => continue,
        }
    }

    if !raw {
        println!("\nDetached.");
    }

    Ok(())
}

/// Send a command to the server
async fn cmd_send(server_dir: &Path, command: &str) -> Result<()> {
    let server_dir = server_dir.canonicalize().context("Invalid server directory")?;
    let paths = ServerPaths::new(&server_dir);

    let state = is_running(&paths).context("Server is not running")?;

    if state.pty_master.is_some() {
        // PTY mode
        let mut stream = UnixStream::connect(&paths.socket_path)
            .await
            .context("Failed to connect to PTY socket")?;
        stream.write_all(command.as_bytes()).await?;
        stream.write_all(b"\n").await?;
    } else {
        // Basic mode
        let input_fifo = paths.wrap_dir.join("input");
        let mut fifo = OpenOptions::new()
            .write(true)
            .open(&input_fifo)
            .context("Failed to open input FIFO")?;
        writeln!(fifo, "{}", command)?;
    }

    Ok(())
}

/// Show server status
fn cmd_status(server_dir: &Path) -> Result<()> {
    let server_dir = server_dir.canonicalize().context("Invalid server directory")?;
    let paths = ServerPaths::new(&server_dir);

    if let Some(state) = is_running(&paths) {
        let mode = if state.pty_master.is_some() { "PTY" } else { "basic" };
        println!("● {} running", server_dir.file_name().unwrap().to_string_lossy());
        println!("  PID: {}", state.pid);
        println!("  Mode: {}", mode);
        println!("  Log: {:?}", paths.log_file);

        // Count log lines
        if let Ok(content) = fs::read_to_string(&paths.log_file) {
            println!("  Lines: {}", content.lines().count());
        }
    } else {
        println!("○ {} not running", server_dir.file_name().unwrap().to_string_lossy());
    }

    Ok(())
}

/// Stop the server gracefully
async fn cmd_stop(server_dir: &Path) -> Result<()> {
    let server_dir = server_dir.canonicalize().context("Invalid server directory")?;
    let paths = ServerPaths::new(&server_dir);

    let state = is_running(&paths).context("Server is not running")?;

    println!("Stopping server...");

    // Send stop command
    cmd_send(&server_dir, "stop").await?;

    // Wait for process to exit (up to 60 seconds)
    for _ in 0..60 {
        if kill(Pid::from_raw(state.pid), None).is_err() {
            println!("Server stopped.");
            let _ = fs::remove_dir_all(&paths.wrap_dir);
            return Ok(());
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
    }

    // Force kill if still running
    println!("Force killing...");
    kill(Pid::from_raw(state.pid), Signal::SIGKILL)?;
    let _ = fs::remove_dir_all(&paths.wrap_dir);

    Ok(())
}

/// Show last N lines of log
fn cmd_log(server_dir: &Path, lines: usize) -> Result<()> {
    let server_dir = server_dir.canonicalize().context("Invalid server directory")?;
    let paths = ServerPaths::new(&server_dir);

    if !paths.log_file.exists() {
        bail!("No log file found");
    }

    let content = fs::read_to_string(&paths.log_file)?;
    let all_lines: Vec<&str> = content.lines().collect();
    let start = all_lines.len().saturating_sub(lines);

    for line in &all_lines[start..] {
        println!("{}", line);
    }

    Ok(())
}

/// Tail the log file
async fn cmd_tail(server_dir: &Path) -> Result<()> {
    let server_dir = server_dir.canonicalize().context("Invalid server directory")?;
    let paths = ServerPaths::new(&server_dir);

    if !paths.log_file.exists() {
        bail!("No log file found");
    }

    let running = Arc::new(AtomicBool::new(true));
    let r = running.clone();

    // Handle Ctrl+C
    let mut sigint = signal(SignalKind::interrupt())?;
    tokio::spawn(async move {
        sigint.recv().await;
        r.store(false, Ordering::SeqCst);
    });

    let mut last_pos = 0u64;
    while running.load(Ordering::SeqCst) {
        if let Ok(mut file) = File::open(&paths.log_file) {
            use std::io::Seek;
            let len = file.metadata().map(|m| m.len()).unwrap_or(0);
            if len > last_pos {
                file.seek(std::io::SeekFrom::Start(last_pos))?;
                let mut buf = String::new();
                file.read_to_string(&mut buf)?;
                print!("{}", buf);
                std::io::stdout().flush()?;
                last_pos = len;
            }
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    Ok(())
}

/// List all managed servers
fn cmd_list() -> Result<()> {
    let wrap_base = dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".mcwrap");

    if !wrap_base.exists() {
        println!("No servers managed.");
        return Ok(());
    }

    let mut found = false;
    for entry in fs::read_dir(&wrap_base)? {
        let entry = entry?;
        let state_file = entry.path().join("state.json");
        if let Ok(file) = File::open(&state_file) {
            if let Ok(state) = serde_json::from_reader::<_, ServerState>(file) {
                let is_alive = kill(Pid::from_raw(state.pid), None).is_ok();
                let status = if is_alive { "●" } else { "○" };
                let mode = if state.pty_master.is_some() { "PTY" } else { "basic" };
                println!(
                    "{} {} (PID: {}, {})",
                    status,
                    state.server_dir.display(),
                    state.pid,
                    mode
                );
                found = true;
            }
        }
    }

    if !found {
        println!("No servers managed.");
    }

    Ok(())
}
