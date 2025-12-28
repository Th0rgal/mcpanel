## Testing: Console selection + restart log continuity

This repo has two console backends:
- **SwiftTerm PTY console** (`ConsoleMode` != `Log Tail`) — interactive terminal emulator used in the UI.
- **Log tail** (`Log Tail`) — reads `logs/latest.log` over SSH.

### Text selection in console (SwiftTerm)

#### What should work
- **Mouse drag selects text** in the console output (you should see a highlight/selection).
- **⌘C copies the selection** (paste into Notes/TextEdit to verify).
- Dragging in the console **should not move the window**.

#### How to test
- Build and run: `./build-app.sh`
- Open the **Console** tab and ensure output is visible.
- Try:
  - Click-drag to select a few lines, then `⌘C`, paste elsewhere.
  - Click once, then drag again (selection should consistently work).

#### Debug signal (optional)
In **Debug** builds, selection changes print:
- `[SwiftTerm] selectionChanged`

You can run from Xcode or view stdout/stderr to confirm selection events fire.

---

### Logs after restart (no relaunch required)

#### What should work
- After clicking **Restart**, the console should:
  - show the shutdown/startup sequence,
  - and **continue showing new output after the server comes back** without quitting MCPanel.

#### How to test
- In the Console tab, click **Restart** (or run `restart`).
- Wait for the server to come back online.
- Verify new log lines continue to stream in.

#### Debug signal (optional)
If the console output stalls after restart, a watchdog will force a reattach and may print:
- `[PTY] Watchdog: output stale (...)s. Forcing reattach...`
- `[PTY] Watchdog: timed out waiting for console output after restart.`

---

### Log Tail mode note

When streaming `latest.log` over SSH, we use:
- `tail -n 0 -F ...` (capital **F**) so log streaming survives log rotation/recreate during restarts.

