//
//  VideoLibrary.swift
//  OfflineCinema
//
//  Main state manager for the video library
//

import Foundation
import SwiftUI
import Combine

// MARK: - Library Filter

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case watching = "Watching"
    case finished = "Finished"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "square.stack.fill"
        case .watching: return "play.circle.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }
    
    var iconOutlined: String {
        switch self {
        case .all: return "books.vertical"
        case .watching: return "arrow.right.circle"
        case .finished: return "checkmark.circle"
        }
    }
}

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
    case library(LibraryFilter)
    case collection(UUID)
}

// MARK: - Video Library

@MainActor
class VideoLibrary: ObservableObject {
    // MARK: - Published State
    
    @Published var videos: [Video] = []
    @Published var collections: [VideoCollection] = []
    @Published var selectedSidebar: SidebarSelection = .library(.all)
    @Published var selectedVideo: Video?
    @Published var isPlaying: Bool = false
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var lastImportErrorMessage: String?
    
    // MARK: - Services
    
    private let persistence = PersistenceService()
    private let thumbnailGenerator = ThumbnailGenerator()
    
    // MARK: - Computed Properties
    
    var filteredVideos: [Video] {
        var result: [Video]
        
        switch selectedSidebar {
        case .library(let filter):
            switch filter {
            case .all:
                result = videos
            case .watching:
                result = videos.filter { $0.watchState == .watching }
            case .finished:
                result = videos.filter { $0.watchState == .finished }
            }
            
        case .collection(let id):
            if let collection = collections.first(where: { $0.id == id }) {
                result = videos.filter { collection.videoIds.contains($0.id) }
            } else {
                result = []
            }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Sort by date added (newest first)
        return result.sorted { $0.dateAdded > $1.dateAdded }
    }
    
    var currentFilterTitle: String {
        switch selectedSidebar {
        case .library(let filter):
            return filter.rawValue
        case .collection(let id):
            return collections.first { $0.id == id }?.name ?? "Collection"
        }
    }
    
    var libraryStats: (total: Int, watching: Int, finished: Int) {
        let watching = videos.filter { $0.watchState == .watching }.count
        let finished = videos.filter { $0.watchState == .finished }.count
        return (videos.count, watching, finished)
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadLibrary()
        }
    }
    
    // MARK: - Persistence
    
    func loadLibrary() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let loadedVideos = persistence.loadVideos()
            async let loadedCollections = persistence.loadCollections()
            
            videos = try await loadedVideos
            collections = try await loadedCollections
            
            // Refresh any stale bookmarks in the background
            await refreshStaleBookmarks()
        } catch {
            print("Failed to load library: \(error)")
        }
    }
    
    /// Refresh any stale bookmarks and save if any were updated
    private func refreshStaleBookmarks() async {
        var needsSave = false
        
        for index in videos.indices {
            if videos[index].needsBookmarkRefresh {
                if videos[index].refreshBookmarkIfNeeded() {
                    needsSave = true
                }
            }
        }
        
        if needsSave {
            await saveLibrary()
        }
    }
    
    func saveLibrary() async {
        do {
            try await persistence.saveVideos(videos)
            try await persistence.saveCollections(collections)
        } catch {
            print("Failed to save library: \(error)")
        }
    }
    
    // MARK: - Video Management
    
    func importVideo(from url: URL) async {
        // Check if video already exists (compare by path to handle stale bookmarks)
        let importPath = url.standardizedFileURL.path
        if videos.contains(where: { video in
            guard let existingURL = video.resolvedURL else { return false }
            return existingURL.standardizedFileURL.path == importPath
        }) {
            return
        }
        
        // Start security-scoped access
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Generate metadata
        let metadata = await thumbnailGenerator.generateMetadata(for: url)
        
        // If there's no decodable video track, don't import (it will play audio-only / fail thumbnails).
        if !metadata.hasVideoTrack {
            lastImportErrorMessage = "This file doesn't contain a decodable video track. Try an MP4/MOV with H.264 or HEVC video."
            return
        }
        
        // Create video entry
        let video = Video(
            title: url.deletingPathExtension().lastPathComponent,
            url: url,
            duration: metadata.duration,
            thumbnailData: metadata.thumbnailData,
            dateAdded: Date(),
            watchState: .unwatched,
            fileSize: metadata.fileSize,
            resolution: metadata.resolution
        )
        
        videos.append(video)
        await saveLibrary()
    }
    
    func removeVideo(_ video: Video) async {
        videos.removeAll { $0.id == video.id }
        
        // Remove from all collections
        for i in collections.indices {
            collections[i].removeVideo(video.id)
        }
        
        await saveLibrary()
    }
    
    func updateVideo(_ video: Video) async {
        if let index = videos.firstIndex(where: { $0.id == video.id }) {
            videos[index] = video
            await saveLibrary()
        }
    }
    
    func updateWatchProgress(for video: Video, position: TimeInterval) async {
        guard var updatedVideo = videos.first(where: { $0.id == video.id }) else { return }
        
        updatedVideo.watchProgress = WatchProgress(position: position)
        
        // Auto-update watch state based on progress
        if updatedVideo.duration > 0 {
            let progress = position / updatedVideo.duration
            if progress > 0.95 {
                updatedVideo.watchState = .finished
            } else if progress > 0.01 && updatedVideo.watchState == .unwatched {
                updatedVideo.watchState = .watching
            }
        }
        
        await updateVideo(updatedVideo)
    }
    
    func markAsFinished(_ video: Video) async {
        guard var updatedVideo = videos.first(where: { $0.id == video.id }) else { return }
        updatedVideo.watchState = .finished
        await updateVideo(updatedVideo)
    }
    
    func markAsUnwatched(_ video: Video) async {
        guard var updatedVideo = videos.first(where: { $0.id == video.id }) else { return }
        updatedVideo.watchState = .unwatched
        updatedVideo.watchProgress = nil
        await updateVideo(updatedVideo)
    }
    
    // MARK: - Collection Management
    
    func createCollection(name: String, icon: String = "folder.fill", color: String = "6366F1") async {
        let collection = VideoCollection(name: name, icon: icon, color: color)
        collections.append(collection)
        await saveLibrary()
    }
    
    func deleteCollection(_ collection: VideoCollection) async {
        collections.removeAll { $0.id == collection.id }
        
        // Reset selection if needed
        if case .collection(let id) = selectedSidebar, id == collection.id {
            selectedSidebar = .library(.all)
        }
        
        await saveLibrary()
    }
    
    func addToCollection(_ video: Video, collection: VideoCollection) async {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].addVideo(video.id)
            await saveLibrary()
        }
    }
    
    func removeFromCollection(_ video: Video, collection: VideoCollection) async {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].removeVideo(video.id)
            await saveLibrary()
        }
    }
    
    func renameCollection(_ collection: VideoCollection, to name: String) async {
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index].name = name
            await saveLibrary()
        }
    }
    
    // MARK: - Playback
    
    func playVideo(_ video: Video) {
        selectedVideo = video
        isPlaying = true
    }
    
    func stopPlayback() {
        isPlaying = false
    }
}

