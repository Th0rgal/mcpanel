//! PTY handling for mcwrap
//!
//! Spawns the Java process with a real PTY so JLine enables tab completion.
//! The PTY master is exposed via a Unix socket for clients to connect.

use anyhow::{Context, Result};
use nix::libc;
use nix::pty::{openpty, Winsize};
use nix::sys::signal::{signal, SigHandler, Signal};
use nix::sys::wait::{waitpid, WaitPidFlag, WaitStatus};
use nix::unistd::{close, dup2, execvp, fork, setsid, ForkResult, Pid};
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io::{Read as IoRead, Write as IoWrite};
use std::os::fd::{AsRawFd, BorrowedFd, IntoRawFd, RawFd};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

pub struct PtySpawnResult {
    pub child_pid: i32,
}

/// Spawn a process with a PTY and expose it via Unix socket
pub fn spawn_with_pty(
    server_dir: &Path,
    java_args: &[String],
    log_file: &Path,
    socket_path: &Path,
) -> Result<PtySpawnResult> {
    // Create PTY pair
    let winsize = Winsize {
        ws_row: 24,
        ws_col: 80,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };

    let pty = openpty(Some(&winsize), None).context("Failed to create PTY")?;
    let master_fd = pty.master;
    let slave_fd = pty.slave;

    // Fork
    match unsafe { fork() }.context("Fork failed")? {
        ForkResult::Parent { child } => {
            // Parent process
            // Close slave end
            drop(slave_fd);

            let master_raw = master_fd.into_raw_fd();

            // Spawn the daemon process that manages the PTY
            spawn_pty_daemon(master_raw, child, log_file, socket_path)?;

            Ok(PtySpawnResult {
                child_pid: child.as_raw() as i32,
            })
        }
        ForkResult::Child => {
            // Child process - becomes Java
            // Close master end
            drop(master_fd);

            // Create new session
            setsid().ok();

            // Set slave as controlling terminal
            let slave_raw = slave_fd.as_raw_fd();

            // Make slave the controlling terminal
            unsafe {
                libc::ioctl(slave_raw, libc::TIOCSCTTY as libc::c_ulong, 0);
            }

            // Redirect stdio to slave PTY
            dup2(slave_raw, 0).ok(); // stdin
            dup2(slave_raw, 1).ok(); // stdout
            dup2(slave_raw, 2).ok(); // stderr

            if slave_raw > 2 {
                drop(slave_fd);
            }

            // Change to server directory
            std::env::set_current_dir(server_dir).ok();

            // Set environment
            std::env::set_var("TERM", "xterm-256color");
            std::env::set_var("COLORTERM", "truecolor");

            // Build args for execvp
            let program = CString::new("java").unwrap();
            let args: Vec<CString> = std::iter::once(CString::new("java").unwrap())
                .chain(java_args.iter().map(|a| CString::new(a.as_str()).unwrap()))
                .collect();

            // Execute Java
            execvp(&program, &args).expect("execvp failed");
            unreachable!()
        }
    }
}

/// Daemon process that manages the PTY master and exposes it via socket
fn spawn_pty_daemon(
    master_fd: RawFd,
    child_pid: Pid,
    log_file: &Path,
    socket_path: &Path,
) -> Result<()> {
    // Remove old socket if exists
    let _ = fs::remove_file(socket_path);

    // Double fork to daemonize
    match unsafe { fork() }.context("Daemon fork failed")? {
        ForkResult::Parent { .. } => {
            // Original parent returns immediately
            // Close our copy of master
            unsafe { libc::close(master_fd) };
            return Ok(());
        }
        ForkResult::Child => {
            // Daemon process
            setsid().ok();

            // Second fork to prevent zombie
            match unsafe { fork() } {
                Ok(ForkResult::Parent { .. }) => {
                    std::process::exit(0);
                }
                Ok(ForkResult::Child) => {
                    // This is the actual daemon
                }
                Err(_) => std::process::exit(1),
            }
        }
    }

    // Now we're the daemon - manage the PTY

    // Ignore SIGHUP
    unsafe {
        signal(Signal::SIGHUP, SigHandler::SigIgn).ok();
    }

    // Open log file
    let mut log = OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file)
        .unwrap_or_else(|_| File::create("/dev/null").unwrap());

    // Create Unix socket for clients
    let listener = UnixListener::bind(socket_path).expect("Failed to bind socket");
    listener.set_nonblocking(true).ok();

    // Track connected clients
    let running = Arc::new(AtomicBool::new(true));
    let clients: Arc<std::sync::Mutex<Vec<UnixStream>>> =
        Arc::new(std::sync::Mutex::new(Vec::new()));

    // Thread to accept new connections
    let clients_clone = clients.clone();
    let running_clone = running.clone();
    thread::spawn(move || {
        while running_clone.load(Ordering::SeqCst) {
            match listener.accept() {
                Ok((stream, _)) => {
                    stream.set_nonblocking(true).ok();
                    clients_clone.lock().unwrap().push(stream);
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(50));
                }
                Err(_) => break,
            }
        }
    });

    // Thread to read from clients and write to PTY
    let clients_clone = clients.clone();
    let running_clone = running.clone();
    thread::spawn(move || {
        let mut buf = [0u8; 1024];
        while running_clone.load(Ordering::SeqCst) {
            let mut to_remove = Vec::new();
            {
                let mut clients = clients_clone.lock().unwrap();
                for (i, client) in clients.iter_mut().enumerate() {
                    match client.read(&mut buf) {
                        Ok(0) => to_remove.push(i),
                        Ok(n) => {
                            // Write to PTY master using libc
                            unsafe {
                                libc::write(
                                    master_fd,
                                    buf[..n].as_ptr() as *const libc::c_void,
                                    n,
                                );
                            }
                        }
                        Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                        Err(_) => to_remove.push(i),
                    }
                }
                // Remove disconnected clients (in reverse order)
                for i in to_remove.into_iter().rev() {
                    clients.remove(i);
                }
            }
            thread::sleep(Duration::from_millis(10));
        }
    });

    // Main loop: read from PTY and broadcast to clients + log
    let mut buf = [0u8; 4096];
    loop {
        // Check if child is still alive
        match waitpid(child_pid, Some(WaitPidFlag::WNOHANG)) {
            Ok(WaitStatus::Exited(_, _)) | Ok(WaitStatus::Signaled(_, _, _)) => {
                // Child exited
                running.store(false, Ordering::SeqCst);
                break;
            }
            _ => {}
        }

        // Read from PTY master using libc
        let n = unsafe { libc::read(master_fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len()) };

        if n == 0 {
            // EOF
            running.store(false, Ordering::SeqCst);
            break;
        } else if n > 0 {
            let data = &buf[..n as usize];

            // Write to log (filter cursor codes but keep colors)
            let filtered = filter_for_log(data);
            log.write_all(&filtered).ok();
            log.flush().ok();

            // Broadcast to all clients
            let mut clients = clients.lock().unwrap();
            let mut to_remove = Vec::new();
            for (i, client) in clients.iter_mut().enumerate() {
                if client.write_all(data).is_err() {
                    to_remove.push(i);
                }
            }
            for i in to_remove.into_iter().rev() {
                clients.remove(i);
            }
        } else {
            // Error
            let err = std::io::Error::last_os_error();
            if err.kind() == std::io::ErrorKind::WouldBlock
                || err.kind() == std::io::ErrorKind::Interrupted
            {
                thread::sleep(Duration::from_millis(10));
            } else {
                running.store(false, Ordering::SeqCst);
                break;
            }
        }
    }

    // Cleanup
    unsafe { libc::close(master_fd) };
    let _ = fs::remove_file(socket_path);

    std::process::exit(0);
}

/// Filter ANSI codes for log file - keep colors, remove cursor movement and prompts
fn filter_for_log(data: &[u8]) -> Vec<u8> {
    let mut result = Vec::with_capacity(data.len());
    let mut i = 0;
    let mut line_start = true;

    while i < data.len() {
        // Skip Minecraft's "> " prompt at start of lines
        if line_start && i + 1 < data.len() && data[i] == b'>' && data[i + 1] == b' ' {
            i += 2;
            // Skip any following newline
            if i < data.len() && data[i] == b'\n' {
                i += 1;
            }
            continue;
        }

        if data[i] == 0x1b && i + 1 < data.len() && data[i + 1] == b'[' {
            // Start of CSI sequence
            let start = i;
            i += 2;

            // Find end of sequence
            while i < data.len() {
                let c = data[i];
                i += 1;
                if (0x40..=0x7E).contains(&c) {
                    // End of CSI sequence
                    // Keep SGR (color) sequences ending in 'm'
                    if c == b'm' {
                        result.extend_from_slice(&data[start..i]);
                    }
                    // Skip cursor movement: H, f, A, B, C, D, E, F, G, J, K, S, T, s, u
                    break;
                }
            }
            line_start = false;
        } else if data[i] == b'\r' {
            // Skip CR entirely - we'll use LF for newlines
            i += 1;
        } else if data[i] == b'\n' {
            // Only add newline if we have content (avoid double newlines)
            if !result.is_empty() && result.last() != Some(&b'\n') {
                result.push(b'\n');
            }
            line_start = true;
            i += 1;
        } else {
            result.push(data[i]);
            line_start = false;
            i += 1;
        }
    }

    result
}
