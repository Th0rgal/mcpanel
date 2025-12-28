//
//  WindowStateObserver.swift
//  MCPanel
//
//  Observes NSWindow fullscreen state for SwiftUI layouts.
//

import SwiftUI
import AppKit

struct WindowStateObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.refresh()
    }

    final class Coordinator {
        private var isFullScreen: Binding<Bool>
        private weak var view: NSView?
        private weak var window: NSWindow?
        private var tokens: [NSObjectProtocol] = []

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        func attach(to view: NSView) {
            self.view = view
            guard let w = view.window else { return }
            if window === w { return }
            window = w
            installObservers(for: w)
            refresh()
        }

        func refresh() {
            guard let w = window else { return }
            let fs = w.styleMask.contains(.fullScreen)
            if isFullScreen.wrappedValue != fs {
                isFullScreen.wrappedValue = fs
            }
        }

        private func installObservers(for window: NSWindow) {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            tokens.removeAll()

            let center = NotificationCenter.default
            tokens.append(
                center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.refresh()
                }
            )
            tokens.append(
                center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.refresh()
                }
            )
            tokens.append(
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.refresh()
                }
            )
        }

        deinit {
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}


