//
//  AppKitSplitHost.swift
//  OfflineCinema
//
//  AppKit window structure for native sidebar rendering:
//  NSSplitViewController + NSSplitViewItem(sidebarWithViewController:)
//

import SwiftUI
import AppKit

struct AppKitSplitHostView: NSViewControllerRepresentable {
    @EnvironmentObject var library: VideoLibrary

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let splitVC = NSSplitViewController()
        splitVC.splitView.isVertical = true
        splitVC.splitView.dividerStyle = .thin

        let sidebarHosting = NSHostingController(rootView: SidebarView().environmentObject(library))
        let detailHosting = NSHostingController(rootView: LibraryDetailView().environmentObject(library))

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = false

        let detailItem = NSSplitViewItem(viewController: detailHosting)
        detailItem.minimumThickness = 600

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(detailItem)

        return splitVC
    }

    func updateNSViewController(_ nsViewController: NSSplitViewController, context: Context) {
        // SwiftUI updates occur via EnvironmentObject.
    }
}

/// Allows configuring the NSWindow from SwiftUI content.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v] in
            guard let window = v?.window else { return }
            configure(window)
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            configure(window)
        }
    }

    private func configure(_ window: NSWindow) {
        // Modern titlebar integration (Books-style) — no toolbar, content under titlebar
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        
        // Remove toolbar to eliminate glass titlebar effect
        window.toolbar = nil
    }
}


