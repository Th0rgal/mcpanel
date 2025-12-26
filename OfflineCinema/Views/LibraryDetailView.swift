//
//  LibraryDetailView.swift
//  OfflineCinema
//
//  Detail/content area hosted inside the AppKit split view.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct LibraryDetailView: View {
    @EnvironmentObject var library: VideoLibrary
    @State private var showFilePicker = false
    @State private var dragOver = false

    var body: some View {
        ZStack {
            if library.isPlaying, let video = library.selectedVideo {
                VideoPlayerView(video: video)
                    .transition(.opacity)
            } else {
                ZStack {
                    if library.videos.isEmpty {
                        emptyState
                    } else {
                        VideoGridView(videos: library.filteredVideos)
                    }

                    if dragOver {
                        dragOverlay
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: library.isPlaying)
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
        .onReceive(NotificationCenter.default.publisher(for: .importVideo)) { _ in
            showFilePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openVideoFile)) { notification in
            if let url = notification.object as? URL {
                Task {
                    await library.importVideo(from: url)
                    // Use path comparison (consistent with importVideo's duplicate check)
                    let importPath = url.standardizedFileURL.path
                    if let video = library.videos.first(where: { video in
                        guard let existingURL = video.resolvedURL else { return false }
                        return existingURL.standardizedFileURL.path == importPath
                    }) {
                        library.playVideo(video)
                    }
                }
            }
        }
        .alert("Can't Import Video", isPresented: Binding(
            get: { library.lastImportErrorMessage != nil },
            set: { if !$0 { library.lastImportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.lastImportErrorMessage = nil }
        } message: {
            Text(library.lastImportErrorMessage ?? "")
        }
    }

    // MARK: - Empty State (Apple-like)

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(library.currentFilterTitle)
                    .font(.system(size: 28, weight: .bold, design: .serif))

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            VStack(spacing: 20) {
                Spacer()

                Image(systemName: dragOver ? "arrow.down.circle" : "film.stack")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundColor(.secondary.opacity(0.6))
                    .scaleEffect(dragOver ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: dragOver)

                VStack(spacing: 6) {
                    Text("No Videos")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary.opacity(0.9))

                    Text("Drag videos here or click to browse")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                showFilePicker = true
            }
        }
        .background {
            if dragOver {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2)
                    .padding(20)
            }
        }
    }

    private var dragOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "DC2626").opacity(0.1))

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(Color(hex: "DC2626"))

                Text("Drop to add to library")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "DC2626"))
            }
        }
        .transition(.opacity)
    }

    private var supportedVideoTypes: [UTType] {
        // All video formats advertised in Info.plist and README
        [
            .mpeg4Movie,           // .mp4, .m4v
            .quickTimeMovie,       // .mov
            .avi,                  // .avi
            .movie,                // Generic movie type
            UTType("org.matroska.mkv") ?? .movie,     // .mkv (custom UTI in Info.plist)
            UTType("org.webmproject.webm") ?? .movie, // .webm
            UTType("com.microsoft.windows-media-wmv") ?? .movie, // .wmv
            UTType("video.flv") ?? .movie,            // .flv
            UTType("public.3gpp") ?? .movie,          // .3gp
            UTType("public.ogg-video") ?? .movie      // .ogv
        ].compactMap { $0 }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                    // All video formats advertised in Info.plist and README
                    let videoExtensions = [
                        "mp4", "mov", "m4v",  // Apple/MPEG-4
                        "avi",                 // AVI
                        "mkv",                 // Matroska
                        "webm",                // WebM
                        "wmv",                 // Windows Media
                        "flv",                 // Flash Video
                        "3gp", "3gpp",         // 3GPP
                        "ogv", "ogg"           // Ogg Video
                    ]
                    let ext = url.pathExtension.lowercased()

                    if videoExtensions.contains(ext) {
                        Task { @MainActor in
                            await library.importVideo(from: url)
                        }
                    }
                }
                handled = true
            }
        }

        return handled
    }
}


