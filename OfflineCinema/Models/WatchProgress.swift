//
//  WatchProgress.swift
//  OfflineCinema
//
//  Track resume position for videos
//

import Foundation

struct WatchProgress: Codable, Hashable {
    var position: TimeInterval
    var lastWatched: Date
    
    init(position: TimeInterval, lastWatched: Date = Date()) {
        self.position = position
        self.lastWatched = lastWatched
    }
    
    var formattedPosition: String {
        let hours = Int(position) / 3600
        let minutes = (Int(position) % 3600) / 60
        let seconds = Int(position) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedLastWatched: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastWatched, relativeTo: Date())
    }
}

