//
//  UploadManager.swift
//  MCPanel
//
//  Manages file uploads with progress tracking and cancellation support
//

import Foundation
import SwiftUI

// MARK: - Upload Item

struct UploadItem: Identifiable {
    let id = UUID()
    let localURL: URL
    let remotePath: String
    let fileName: String
    let fileSize: Int64
    let securityScopedBookmark: Data?  // Store bookmark for sandbox access
    var bytesUploaded: Int64 = 0
    var status: UploadStatus = .pending

    var progress: Double {
        guard fileSize > 0 else { return 0 }
        return Double(bytesUploaded) / Double(fileSize)
    }

    enum UploadStatus: Equatable {
        case pending
        case uploading
        case completed
        case failed(String)
        case cancelled
    }
}

// MARK: - Upload Manager

@MainActor
class UploadManager: ObservableObject {
    @Published var items: [UploadItem] = []
    @Published var isUploading = false
    @Published var isExpanded = false
    @Published var currentItemIndex: Int = 0

    private var uploadTask: Task<Void, Never>?
    private var isCancelled = false

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    var uploadedBytes: Int64 {
        items.reduce(0) { $0 + $1.bytesUploaded }
    }

    var totalProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(uploadedBytes) / Double(totalBytes)
    }

    var completedCount: Int {
        items.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        items.filter { if case .failed = $0.status { return true }; return false }.count
    }

    var currentFileName: String? {
        guard currentItemIndex < items.count else { return nil }
        return items[currentItemIndex].fileName
    }

    var isComplete: Bool {
        !isUploading && !items.isEmpty && items.allSatisfy { item in
            switch item.status {
            case .completed, .cancelled, .failed:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Public Methods

    func queueUpload(urls: [URL], remotePath: String, ssh: SSHService) {
        // Collect all files (including from folders) with their bookmarks
        var filesToUpload: [(url: URL, relativePath: String, bookmark: Data?)] = []

        for url in urls {
            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Recursively collect files from folder, creating bookmarks for each
                    collectFiles(from: url, basePath: url.deletingLastPathComponent().path, into: &filesToUpload)
                } else {
                    // Create bookmark for single file
                    let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    filesToUpload.append((url, url.lastPathComponent, bookmark))
                }
            }
        }

        // Create upload items with bookmarks for later access
        for (url, relativePath, bookmark) in filesToUpload {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let fullRemotePath = (remotePath as NSString).appendingPathComponent(relativePath)

            let item = UploadItem(
                localURL: url,
                remotePath: fullRemotePath,
                fileName: relativePath,
                fileSize: fileSize,
                securityScopedBookmark: bookmark
            )
            items.append(item)
        }

        // Start upload if not already running
        if !isUploading {
            startUpload(ssh: ssh)
        }
    }

    func cancel() {
        isCancelled = true
        uploadTask?.cancel()

        // Mark pending items as cancelled
        for i in items.indices {
            if items[i].status == .pending || items[i].status == .uploading {
                items[i].status = .cancelled
            }
        }

        isUploading = false
    }

    func dismiss() {
        items.removeAll()
        isExpanded = false
        currentItemIndex = 0
        isCancelled = false
    }

    // MARK: - Private Methods

    private func collectFiles(from folderURL: URL, basePath: String, into files: inout [(url: URL, relativePath: String, bookmark: Data?)]) {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                // Calculate relative path from base
                let relativePath = String(fileURL.path.dropFirst(basePath.count + 1))
                // Create security-scoped bookmark for each file while we have folder access
                let bookmark = try? fileURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                files.append((fileURL, relativePath, bookmark))
            }
        }
    }

    private func startUpload(ssh: SSHService) {
        isUploading = true
        isCancelled = false

        uploadTask = Task {
            for i in items.indices {
                guard !isCancelled && !Task.isCancelled else { break }
                guard items[i].status == .pending else { continue }

                currentItemIndex = i
                items[i].status = .uploading

                do {
                    // Try to resolve bookmark first, fall back to direct URL access
                    var accessedURL: URL? = nil
                    var stopAccessing: (() -> Void)? = nil

                    if let bookmark = items[i].securityScopedBookmark {
                        var isStale = false
                        if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                            if url.startAccessingSecurityScopedResource() {
                                accessedURL = url
                                stopAccessing = { url.stopAccessingSecurityScopedResource() }
                            }
                        }
                    }

                    // Fall back to direct URL if bookmark failed
                    if accessedURL == nil {
                        let url = items[i].localURL
                        if url.startAccessingSecurityScopedResource() {
                            accessedURL = url
                            stopAccessing = { url.stopAccessingSecurityScopedResource() }
                        }
                    }

                    defer {
                        stopAccessing?()
                    }

                    guard let fileURL = accessedURL else {
                        throw NSError(domain: "UploadManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access file"])
                    }

                    // Create parent directory if needed (escape path for shell safety)
                    let parentDir = (items[i].remotePath as NSString).deletingLastPathComponent
                    if parentDir != "/" && !parentDir.isEmpty {
                        let escapedPath = escapeShellPath(parentDir)
                        _ = try? await ssh.execute("mkdir -p \(escapedPath)")
                    }

                    // Upload with progress tracking
                    try await uploadWithProgress(
                        localPath: fileURL.path,
                        remotePath: items[i].remotePath,
                        ssh: ssh,
                        itemIndex: i
                    )

                    items[i].bytesUploaded = items[i].fileSize
                    items[i].status = .completed
                } catch {
                    if !isCancelled {
                        items[i].status = .failed(error.localizedDescription)
                    }
                }
            }

            isUploading = false
        }
    }

    /// Escapes a path for safe use in shell commands
    private func escapeShellPath(_ path: String) -> String {
        // Replace single quotes with '\'' (end quote, escaped quote, start quote)
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func uploadWithProgress(localPath: String, remotePath: String, ssh: SSHService, itemIndex: Int) async throws {
        // For now, use the existing scp upload
        // Progress is simulated based on file size
        // TODO: Implement true progress tracking with rsync or custom SFTP

        let fileSize = items[itemIndex].fileSize

        // Start a progress simulation task
        let progressTask = Task {
            var simulatedProgress: Int64 = 0
            let chunkSize = max(fileSize / 20, 1024) // Update ~20 times or every KB

            while simulatedProgress < fileSize && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                simulatedProgress = min(simulatedProgress + chunkSize, fileSize - 1)
                await MainActor.run {
                    if itemIndex < self.items.count {
                        self.items[itemIndex].bytesUploaded = simulatedProgress
                    }
                }
            }
        }

        defer {
            progressTask.cancel()
        }

        // Perform actual upload
        try await ssh.uploadFile(localPath: localPath, remotePath: remotePath)
    }
}

// MARK: - Byte Formatter

extension Int64 {
    var formattedBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}
