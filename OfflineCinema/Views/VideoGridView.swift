//
//  VideoGridView.swift
//  OfflineCinema
//
//  Grid display of video thumbnails with Books-like layout
//

import SwiftUI
import UniformTypeIdentifiers

// Preference key to track container width
private struct ContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct VideoGridView: View {
    @EnvironmentObject var library: VideoLibrary
    let videos: [Video]
    @State private var showFilePicker = false
    @State private var containerWidth: CGFloat = 600
    
    // Grid constants - CSS flex-like behavior
    private let itemMinWidth: CGFloat = 180
    private let itemMaxWidth: CGFloat = 280
    private let horizontalSpacing: CGFloat = 24
    private let verticalSpacing: CGFloat = 32
    private let horizontalPadding: CGFloat = 24
    
    private var columns: [GridItem] {
        let availableWidth = containerWidth - (horizontalPadding * 2)
        guard availableWidth > 0 else {
            return [GridItem(.flexible(), spacing: horizontalSpacing)]
        }
        // Calculate how many items fit with minimum width + spacing
        let columnCount = max(1, Int((availableWidth + horizontalSpacing) / (itemMinWidth + horizontalSpacing)))
        // Use flexible items with fixed spacing to maintain gaps
        return Array(repeating: GridItem(.flexible(minimum: itemMinWidth, maximum: itemMaxWidth), spacing: horizontalSpacing), count: columnCount)
    }
    
    private var supportedVideoTypes: [UTType] {
        // All video formats advertised in Info.plist and README
        [
            .mpeg4Movie,           // .mp4, .m4v
            .quickTimeMovie,       // .mov
            .avi,                  // .avi
            .movie,                // Generic movie type
            UTType("org.matroska.mkv") ?? .movie,     // .mkv
            UTType("org.webmproject.webm") ?? .movie, // .webm
            UTType("com.microsoft.windows-media-wmv") ?? .movie, // .wmv
            UTType("video.flv") ?? .movie,            // .flv
            UTType("public.3gpp") ?? .movie,          // .3gp
            UTType("public.ogg-video") ?? .movie      // .ogv
        ].compactMap { $0 }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Width tracker - captures actual available width
                Color.clear
                    .frame(height: 0)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ContainerWidthKey.self, value: geo.size.width)
                        }
                    )
                
                // Title header like Books app
                HStack(alignment: .center) {
                    Text(library.currentFilterTitle)
                        .font(.system(size: 32, weight: .bold, design: .serif))
                    
                    Spacer()
                    
                    // Three-dot menu
                    Menu {
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Import Videos...", systemImage: "plus")
                        }
                        
                        Divider()
                        
                        Menu("Sort By") {
                            Button("Date Added") { }
                            Button("Title") { }
                            Button("Duration") { }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 20)
                
                if videos.isEmpty {
                    emptyStateInline
                } else {
                    LazyVGrid(columns: columns, spacing: verticalSpacing) {
                        ForEach(videos) { video in
                            VideoThumbnailCard(video: video)
                                .onTapGesture {
                                    library.selectedVideo = video
                                    library.playVideo(video)
                                }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 24)
                }
            }
        }
        .onPreferenceChange(ContainerWidthKey.self) { width in
            if width > 0 {
                containerWidth = width
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: supportedVideoTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    for url in urls {
                        await library.importVideo(from: url)
                    }
                }
            }
        }
    }
    
    private var emptyStateInline: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No videos in this view")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 300)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(hex: "DC2626").opacity(0.08))
                    .frame(width: 80, height: 80)
                
                Circle()
                    .strokeBorder(Color(hex: "DC2626").opacity(0.15), lineWidth: 1)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(Color(hex: "DC2626").opacity(0.5))
            }
            
            VStack(spacing: 6) {
                Text("No Videos Yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.8))
                
                Text("Import videos to start building your library")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Video Thumbnail Card

struct VideoThumbnailCard: View {
    @EnvironmentObject var library: VideoLibrary
    let video: Video
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail with progress overlay
            thumbnailView
            
            // Info row below thumbnail
            infoRow
        }
        .contextMenu {
            contextMenuContent
        }
    }
    
    // MARK: - Thumbnail
    
    private var thumbnailView: some View {
        ZStack(alignment: .bottom) {
            // Thumbnail image
            Group {
                if let thumbnail = video.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "1F1F1F"), Color(hex: "2D2D2D")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(16/9, contentMode: .fill)
                        .overlay {
                            Image(systemName: "film")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.white.opacity(0.3))
                        }
                }
            }
            .frame(height: 120)
            .clipped()
            
            // Progress bar at bottom
            if video.progressPercentage > 0 && video.watchState != .finished {
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.black.opacity(0.5))
                                .frame(height: 3)
                            
                            Rectangle()
                                .fill(Color(hex: "DC2626"))
                                .frame(width: geo.size.width * video.progressPercentage, height: 3)
                        }
                    }
                }
            }
            
            // Hover overlay with play button
            if isHovered {
                Rectangle()
                    .fill(.black.opacity(0.4))
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .transition(.opacity)
            }
            
            // Duration badge
            HStack {
                Spacer()
                Text(video.formattedDuration)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(.black.opacity(0.7))
                    }
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(isHovered ? 0.3 : 0.15), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25), value: isHovered)
        .onHover { isHovered = $0 }
    }
    
    // MARK: - Info Row
    
    private var infoRow: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // Progress or NEW badge
                if video.watchState == .unwatched {
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(Color(hex: "3B82F6"))
                        }
                } else if video.watchState == .finished {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("Finished")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "22C55E"))
                } else {
                    Text(video.formattedProgress)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                // Title
                Text(video.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Context menu button
            Menu {
                contextMenuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24, height: 24)
        }
        .padding(.top, 10)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            library.playVideo(video)
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        
        Divider()
        
        if video.watchState != .finished {
            Button {
                Task { await library.markAsFinished(video) }
            } label: {
                Label("Mark as Finished", systemImage: "checkmark.circle")
            }
        }
        
        if video.watchState != .unwatched {
            Button {
                Task { await library.markAsUnwatched(video) }
            } label: {
                Label("Mark as Unwatched", systemImage: "circle")
            }
        }
        
        Divider()
        
        if !library.collections.isEmpty {
            Menu("Add to Collection") {
                ForEach(library.collections) { collection in
                    Button {
                        Task { await library.addToCollection(video, collection: collection) }
                    } label: {
                        Label(collection.name, systemImage: collection.icon)
                    }
                    .disabled(collection.contains(video.id))
                }
            }
        }
        
        // Show in Finder
        if let url = video.resolvedURL {
            Button {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            Task { await library.removeVideo(video) }
        } label: {
            Label("Remove from Library", systemImage: "trash")
        }
    }
}

