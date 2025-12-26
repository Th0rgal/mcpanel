//
//  PersistenceService.swift
//  OfflineCinema
//
//  JSON-based persistence for library data
//

import Foundation

actor PersistenceService {
    private let libraryFileName = "library.json"
    private let collectionsFileName = "collections.json"
    
    private var libraryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("OfflineCinema", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder.appendingPathComponent(libraryFileName)
    }
    
    private var collectionsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("OfflineCinema", isDirectory: true)
        return appFolder.appendingPathComponent(collectionsFileName)
    }
    
    // MARK: - Videos
    
    func loadVideos() async throws -> [Video] {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: libraryURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Video].self, from: data)
    }
    
    func saveVideos(_ videos: [Video]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let data = try encoder.encode(videos)
        try data.write(to: libraryURL, options: .atomic)
    }
    
    // MARK: - Collections
    
    func loadCollections() async throws -> [VideoCollection] {
        guard FileManager.default.fileExists(atPath: collectionsURL.path) else {
            return []
        }
        
        let data = try Data(contentsOf: collectionsURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VideoCollection].self, from: data)
    }
    
    func saveCollections(_ collections: [VideoCollection]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let data = try encoder.encode(collections)
        try data.write(to: collectionsURL, options: .atomic)
    }
}

