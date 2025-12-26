//
//  ThumbnailGenerator.swift
//  OfflineCinema
//
//  Generate video thumbnails using AVFoundation
//

import Foundation
import AVFoundation
import AppKit

actor ThumbnailGenerator {
    
    struct VideoMetadata {
        let duration: TimeInterval
        let resolution: VideoResolution?
        let fileSize: Int64
        let thumbnailData: Data?
        let hasVideoTrack: Bool
    }
    
    func generateMetadata(for url: URL) async -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        
        // Get duration
        let duration: TimeInterval
        do {
            let cmDuration = try await asset.load(.duration)
            duration = CMTimeGetSeconds(cmDuration)
        } catch {
            duration = 0
        }
        
        // Get resolution from video track
        let resolution: VideoResolution?
        var hasVideoTrack: Bool = false
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let videoTrack = tracks.first {
                hasVideoTrack = true
                let size = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                
                // Apply transform to get correct dimensions (handles rotation)
                let transformedSize = size.applying(transform)
                let width = abs(Int(transformedSize.width))
                let height = abs(Int(transformedSize.height))
                
                resolution = VideoResolution(width: width, height: height)
            } else {
                hasVideoTrack = false
                resolution = nil
            }
        } catch {
            hasVideoTrack = false
            resolution = nil
        }
        
        // Get file size
        let fileSize: Int64
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            fileSize = Int64(resourceValues.fileSize ?? 0)
        } catch {
            fileSize = 0
        }
        
        // Generate thumbnail
        let thumbnailData = await generateThumbnail(for: url, duration: duration)
        
        return VideoMetadata(
            duration: duration,
            resolution: resolution,
            fileSize: fileSize,
            thumbnailData: thumbnailData,
            hasVideoTrack: hasVideoTrack
        )
    }
    
    /// Generates a thumbnail frame. Avoids zero-tolerance seeking because many assets don't have
    /// keyframes at the exact requested time (which would yield nil thumbnails).
    func generateThumbnail(for url: URL, duration: TimeInterval) async -> Data? {
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 400) // Reasonable thumbnail size
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        
        // Prefer an early keyframe (but not necessarily at 0, which is often black).
        let candidateTimes: [TimeInterval] = {
            let d = max(0, duration)
            if d <= 0 { return [0] }
            let t1 = min(max(2, d * 0.03), max(0, d - 1))
            let t2 = min(max(5, d * 0.08), max(0, d - 1))
            return [t1, t2, 0]
        }()
        
        for t in candidateTimes {
            let cmTime = CMTime(seconds: max(0, t), preferredTimescale: 600)
            do {
                let (cgImage, _) = try await imageGenerator.image(at: cmTime)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                
                // Convert to JPEG data
                guard let tiffData = nsImage.tiffRepresentation,
                      let bitmapRep = NSBitmapImageRep(data: tiffData) else {
                    continue
                }
                
                if let jpeg = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
                    return jpeg
                }
            } catch {
                continue
            }
        }
        
        return nil
    }
}

