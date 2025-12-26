//
//  MCPanelApp.swift
//  MCPanel
//
//  A beautiful native macOS Minecraft server control panel
//

import SwiftUI
import AppKit

@main
struct MCPanelApp: App {
    @StateObject private var serverManager = ServerManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(serverManager)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Server...") {
                    NotificationCenter.default.post(name: .addServer, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Server") {
                Button("Refresh Status") {
                    NotificationCenter.default.post(name: .refreshStatus, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Start Server") {
                    NotificationCenter.default.post(name: .startServer, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Stop Server") {
                    NotificationCenter.default.post(name: .stopServer, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)

                Button("Restart Server") {
                    NotificationCenter.default.post(name: .restartServer, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Divider()

                Button("Console") {
                    NotificationCenter.default.post(name: .showConsole, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Plugins") {
                    NotificationCenter.default.post(name: .showPlugins, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Files") {
                    NotificationCenter.default.post(name: .showFiles, object: nil)
                }
                .keyboardShortcut("3", modifiers: .command)
            }

            CommandGroup(before: .windowList) {
                ShowMainWindowButton()
                Divider()
            }
        }
    }
}

// MARK: - Show Main Window Button

struct ShowMainWindowButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("MCPanel") {
            openWindow(id: "main")
        }
        .keyboardShortcut("0", modifiers: .command)
        .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
            openWindow(id: "main")
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let trafficLights = TrafficLightsPositioner(offsetX: 14, offsetY: -10)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                self.configureWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                if window.contentView != nil &&
                   !(window is NSPanel) &&
                   window.styleMask.contains(.titled) {
                    window.makeKeyAndOrderFront(nil)
                    configureWindow(window)
                    return true
                }
            }
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        for window in NSApplication.shared.windows {
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func configureWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        if window.title.isEmpty {
            window.title = "MCPanel"
        }

        window.toolbar = nil
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true

        trafficLights.attach(to: window)
    }
}

// MARK: - Traffic Lights Positioning

@MainActor
final class TrafficLightsPositioner {
    private let offsetX: CGFloat
    private let offsetY: CGFloat
    private var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    init(offsetX: CGFloat, offsetY: CGFloat) {
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    func attach(to window: NSWindow) {
        let id = ObjectIdentifier(window)
        if observers[id] != nil { return }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.apply(to: window)
        }

        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = [
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.apply(to: window)
                }
            },
            center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.apply(to: window)
                }
            },
            center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window else { return }
                    self.apply(to: window)
                }
            }
        ]

        let closeObserver = center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notification in
            guard let closingWindow = notification.object as? NSWindow else { return }
            let closingId = ObjectIdentifier(closingWindow)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let tokens = self.observers[closingId] {
                    tokens.forEach { NotificationCenter.default.removeObserver($0) }
                    self.observers.removeValue(forKey: closingId)
                }
            }
        }
        tokens.append(closeObserver)

        observers[id] = tokens
    }

    private func apply(to window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let mini = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton) else { return }

        let baseline = Baseline.ensure(on: window, close: close.frame.origin, mini: mini.frame.origin, zoom: zoom.frame.origin)

        close.setFrameOrigin(NSPoint(x: baseline.close.x + offsetX, y: baseline.close.y + offsetY))
        mini.setFrameOrigin(NSPoint(x: baseline.mini.x + offsetX, y: baseline.mini.y + offsetY))
        zoom.setFrameOrigin(NSPoint(x: baseline.zoom.x + offsetX, y: baseline.zoom.y + offsetY))
    }

    private final class Baseline: NSObject {
        let close: NSPoint
        let mini: NSPoint
        let zoom: NSPoint

        init(close: NSPoint, mini: NSPoint, zoom: NSPoint) {
            self.close = close
            self.mini = mini
            self.zoom = zoom
        }

        static func ensure(on window: NSWindow, close: NSPoint, mini: NSPoint, zoom: NSPoint) -> Baseline {
            if let existing = objc_getAssociatedObject(window, &baselineKey) as? Baseline {
                return existing
            }
            let created = Baseline(close: close, mini: mini, zoom: zoom)
            objc_setAssociatedObject(window, &baselineKey, created, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return created
        }
    }
}

private var baselineKey: UInt8 = 0

// MARK: - Notification Names

extension Notification.Name {
    static let addServer = Notification.Name("addServer")
    static let showAddServer = Notification.Name("showAddServer")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let showMainWindow = Notification.Name("showMainWindow")
    static let refreshStatus = Notification.Name("refreshStatus")
    static let startServer = Notification.Name("startServer")
    static let stopServer = Notification.Name("stopServer")
    static let restartServer = Notification.Name("restartServer")
    static let showConsole = Notification.Name("showConsole")
    static let showPlugins = Notification.Name("showPlugins")
    static let showFiles = Notification.Name("showFiles")
}
