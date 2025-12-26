//
//  ContentView.swift
//  OfflineCinema
//
//  Main content view with Books-inspired glass UI layout
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var library: VideoLibrary
    
    var body: some View {
        BooksChromeView()
            .environmentObject(library)
            .frame(minWidth: 900, minHeight: 600)
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
        .environmentObject(VideoLibrary())
        .frame(width: 1100, height: 750)
}

// MARK: - Books-style chrome (floating sidebar under titlebar)

private struct BooksChromeView: View {
    @EnvironmentObject var library: VideoLibrary
    @State private var isWindowFullScreen = false
    @SceneStorage("sidebarVisible") private var sidebarVisible: Bool = true
    
    private let sidebarWidth: CGFloat = 220
    private let outerInset: CGFloat = 10
    // This controls how "inside" the traffic lights feel. Needs to be > 0 so the panel is inset,
    // but small enough that lights still sit over the glass.
    private let topInset: CGFloat = 10
    private let gap: CGFloat = 12
    private let cornerRadius: CGFloat = 12
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Window background (edge-to-edge)
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
            
            // Detail content laid out edge-to-edge, but shifted right to make room for the floating sidebar
            LibraryDetailView()
                .environmentObject(library)
                .padding(.leading, leftInset)
                // Keep right/bottom breathing room like Books, but DO NOT inset from the top
                // (insetting the top makes a visible “top bar” appear).
                .padding(.trailing, (isWindowFullScreen || library.isPlaying) ? 0 : outerInset)
                .padding(.bottom, (isWindowFullScreen || library.isPlaying) ? 0 : outerInset)
                .padding(.top, 0)
                // The detail panel is the “dark gray interior”. Round its bottom corners so it matches
                // the window’s rounded geometry instead of showing square corners.
                .background { detailPanelShape.fill(detailPanelFill) }
                .clipShape(detailPanelShape)
                .overlay { detailPanelShape.strokeBorder(.white.opacity(library.isPlaying ? 0.0 : 0.05), lineWidth: 1) }
            
            // Floating sidebar panel (inset, concentric corners, under-titlebar)
            if showSidebar {
                SidebarView()
                    .environmentObject(library)
                    .frame(width: sidebarWidth)
                    .background {
                        ZStack {
                            // Dark base so it doesn't feel "see-through" on dark windows
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color(hex: "1D1D1F").opacity(0.65))
                            // System Liquid Glass (wallpaper/theme-derived tint)
                            GlassBackground(material: .sidebar, blendingMode: .withinWindow)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    // No explicit border: Books relies on shadow + glass edge contrast.
                    .overlay {
                        // Subtle inner highlight like system glass edges
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
                    // Small top inset so the panel sits under the traffic lights visually
                    .padding(.top, topInset)
            }
        }
        // Ensure the floating sidebar can extend under the titlebar (traffic lights appear “inside”)
        .ignoresSafeArea(.container, edges: .top)
        // Track fullscreen to hide sidebar + remove insets
        .overlay(WindowStateObserver(isFullScreen: $isWindowFullScreen).frame(width: 0, height: 0))
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarVisible.toggle()
            }
        }
    }
    
    private var showSidebar: Bool {
        !isWindowFullScreen && sidebarVisible
    }
    
    private var leftInset: CGFloat {
        // Edge-to-edge when fullscreen or playing video with sidebar hidden
        if isWindowFullScreen || (library.isPlaying && !sidebarVisible) { return 0 }
        
        if showSidebar {
            // When playing video, remove the gap so canvas starts right at sidebar edge
            let effectiveGap = library.isPlaying ? 0 : gap
            return outerInset + sidebarWidth + effectiveGap
        }
        return outerInset
    }
    
    private var detailPanelShape: UnevenRoundedRectangle {
        // Keep top corners square (content reaches the titlebar), round the bottom corners.
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0
        )
    }
    
    private var detailPanelFill: Color {
        // When playing, we want the player to feel edge-to-edge; fill with black.
        library.isPlaying ? .black : Color(hex: "161618")
    }
}

