//
//  Video.swift
//  OfflineCinema
//
//  Video model with metadata and watch state
//

import Foundation
import AppKit

// MARK: - Watch State

enum WatchState: String, Codable, CaseIterable, Identifiable {
    case unwatched = "Unwatched"
    case watching = "Watching"
    case finished = "Finished"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .unwatched: return "circle"
        case .watching: return "play.circle.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Video Model

struct Video: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var urlBookmarkData: Data?
    var duration: TimeInterval
    var thumbnailData: Data?
    var dateAdded: Date
    var watchState: WatchState
    var watchProgress: WatchProgress?
    var fileSize: Int64
    var resolution: VideoResolution?
    
    // Non-persisted URL resolved from bookmark
    // Returns (url, isStale) tuple - stale bookmarks are still valid for the current session
    var resolvedURLWithStaleFlag: (url: URL, isStale: Bool)? {
        guard let bookmarkData = urlBookmarkData else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            // Per Apple docs: stale bookmarks still return a usable URL for the current session
            // The staleness flag just indicates the bookmark data should be refreshed
            return (url, isStale)
        } catch {
            return nil
        }
    }
    
    // Convenience property for most use cases (playback, Finder reveal, etc.)
    var resolvedURL: URL? {
        resolvedURLWithStaleFlag?.url
    }
    
    // Check if bookmark needs refresh
    var needsBookmarkRefresh: Bool {
        resolvedURLWithStaleFlag?.isStale ?? false
    }
    
    // Computed properties
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var progressPercentage: Double {
        guard let progress = watchProgress, duration > 0 else { return 0 }
        return min(progress.position / duration, 1.0)
    }
    
    var formattedProgress: String {
        let percentage = Int(progressPercentage * 100)
        if percentage == 0 && watchState == .unwatched {
            return "NEW"
        }
        return "\(percentage) %"
    }
    
    var thumbnail: NSImage? {
        guard let data = thumbnailData else { return nil }
        return NSImage(data: data)
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        title: String,
        url: URL? = nil,
        urlBookmarkData: Data? = nil,
        duration: TimeInterval = 0,
        thumbnailData: Data? = nil,
        dateAdded: Date = Date(),
        watchState: WatchState = .unwatched,
        watchProgress: WatchProgress? = nil,
        fileSize: Int64 = 0,
        resolution: VideoResolution? = nil
    ) {
        self.id = id
        self.title = title
        self.duration = duration
        self.thumbnailData = thumbnailData
        self.dateAdded = dateAdded
        self.watchState = watchState
        self.watchProgress = watchProgress
        self.fileSize = fileSize
        self.resolution = resolution
        
        // Create bookmark from URL if provided
        if let url = url {
            self.urlBookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } else {
            self.urlBookmarkData = urlBookmarkData
        }
    }
    
    // MARK: - Bookmark Management
    
    /// Refresh the bookmark if it's stale. Returns true if refresh was successful.
    mutating func refreshBookmarkIfNeeded() -> Bool {
        guard let (url, isStale) = resolvedURLWithStaleFlag, isStale else {
            return false // Not stale or can't resolve
        }
        
        // Must start security-scoped access before creating a new bookmark
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Try to create a fresh bookmark
        if let newBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            urlBookmarkData = newBookmark
            return true
        }
        return false
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Video Resolution

struct VideoResolution: Codable, Hashable {
    let width: Int
    let height: Int
    
    var description: String {
        if height >= 2160 {
            return "4K"
        } else if height >= 1440 {
            return "1440p"
        } else if height >= 1080 {
            return "1080p"
        } else if height >= 720 {
            return "720p"
        } else if height >= 480 {
            return "480p"
        } else {
            return "\(width)×\(height)"
        }
    }
    
    var aspectRatio: CGFloat {
        guard height > 0 else { return 16/9 }
        return CGFloat(width) / CGFloat(height)
    }
}


