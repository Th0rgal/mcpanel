//
//  ContentView.swift
//  MCPanel
//
//  Main content view with Books-inspired glass UI layout
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var showAddServer = false

    var body: some View {
        ZStack {
            if serverManager.servers.isEmpty && !serverManager.isLoading {
                // Show onboarding when no servers configured
                OnboardingView(isPresented: .constant(true))
                    .environmentObject(serverManager)
            } else {
                MainChromeView()
                    .environmentObject(serverManager)
            }

            // Full-screen add server overlay
            if showAddServer && !serverManager.servers.isEmpty {
                OnboardingView(isPresented: $showAddServer)
                    .environmentObject(serverManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onReceive(NotificationCenter.default.publisher(for: .showAddServer)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                showAddServer = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addServer)) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                showAddServer = true
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerManager())
        .frame(width: 1200, height: 800)
}

// MARK: - Main Chrome View

private struct MainChromeView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var isWindowFullScreen = false
    @SceneStorage("sidebarVisible") private var sidebarVisible: Bool = true

    private let sidebarWidth: CGFloat = 220
    private let outerInset: CGFloat = 10
    private let topInset: CGFloat = 10
    private let gap: CGFloat = 12
    private let cornerRadius: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Window background
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "17171A"), Color(hex: "121214")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 520
                )
            }
            .ignoresSafeArea()

            // Main content area
            ServerDetailView()
                .environmentObject(serverManager)
                .padding(.leading, leftInset)
                .padding(.trailing, isWindowFullScreen ? 0 : outerInset)
                .padding(.bottom, isWindowFullScreen ? 0 : outerInset)
                .padding(.top, 0)
                .background { detailPanelShape.fill(Color(hex: "161618")) }
                .clipShape(detailPanelShape)
                .overlay { detailPanelShape.strokeBorder(.white.opacity(0.05), lineWidth: 1) }

            // Floating sidebar
            if showSidebar {
                SidebarView()
                    .environmentObject(serverManager)
                    .frame(width: sidebarWidth)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color(hex: "1D1D1F").opacity(0.65))
                            GlassBackground(material: .sidebar, blendingMode: .withinWindow)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.14),
                                        .white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 14)
                    .padding(.leading, outerInset)
                    .padding(.bottom, outerInset)
                    .padding(.top, topInset)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .overlay(WindowStateObserver(isFullScreen: $isWindowFullScreen).frame(width: 0, height: 0))
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarVisible.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshStatus)) { _ in
            Task {
                await serverManager.refreshAllServers()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startServer)) { _ in
            if let server = serverManager.selectedServer {
                Task { await serverManager.startServer(server) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopServer)) { _ in
            if let server = serverManager.selectedServer {
                Task { await serverManager.stopServer(server) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .restartServer)) { _ in
            if let server = serverManager.selectedServer {
                Task { await serverManager.restartServer(server) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showConsole)) { _ in
            serverManager.selectedTab = .console
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPlugins)) { _ in
            serverManager.selectedTab = .plugins
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFiles)) { _ in
            serverManager.selectedTab = .files
        }
    }

    private var showSidebar: Bool {
        !isWindowFullScreen && sidebarVisible
    }

    private var leftInset: CGFloat {
        if isWindowFullScreen { return 0 }
        if showSidebar {
            return outerInset + sidebarWidth + gap
        }
        return outerInset
    }

    private var detailPanelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0
        )
    }
}
