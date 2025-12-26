//
//  Collection.swift
//  OfflineCinema
//
//  User-created video collections
//

import Foundation
import SwiftUI

struct VideoCollection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var videoIds: [UUID]
    var dateCreated: Date
    var icon: String
    var color: String
    
    init(
        id: UUID = UUID(),
        name: String,
        videoIds: [UUID] = [],
        dateCreated: Date = Date(),
        icon: String = "folder.fill",
        color: String = "6366F1"
    ) {
        self.id = id
        self.name = name
        self.videoIds = videoIds
        self.dateCreated = dateCreated
        self.icon = icon
        self.color = color
    }
    
    var videoCount: Int {
        videoIds.count
    }
    
    var accentColor: Color {
        Color(hex: color)
    }
    
    mutating func addVideo(_ videoId: UUID) {
        if !videoIds.contains(videoId) {
            videoIds.append(videoId)
        }
    }
    
    mutating func removeVideo(_ videoId: UUID) {
        videoIds.removeAll { $0 == videoId }
    }
    
    func contains(_ videoId: UUID) -> Bool {
        videoIds.contains(videoId)
    }
}

// MARK: - Preset Collection Icons

enum CollectionIcon: String, CaseIterable, Identifiable {
    case folder = "folder.fill"
    case heart = "heart.fill"
    case star = "star.fill"
    case film = "film.fill"
    case tv = "tv.fill"
    case popcorn = "popcorn.fill"
    case bookmark = "bookmark.fill"
    case flag = "flag.fill"
    
    var id: String { rawValue }
}

// MARK: - Preset Collection Colors

enum CollectionColor: String, CaseIterable, Identifiable {
    case indigo = "6366F1"
    case purple = "A855F7"
    case pink = "EC4899"
    case red = "EF4444"
    case orange = "F97316"
    case yellow = "EAB308"
    case green = "22C55E"
    case teal = "14B8A6"
    case blue = "3B82F6"
    
    var id: String { rawValue }
    
    var color: Color {
        Color(hex: rawValue)
    }
}

