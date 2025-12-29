//
//  FileBrowserView.swift
//  MCPanel
//
//  Native file browser for server files
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @EnvironmentObject var serverManager: ServerManager
    @StateObject private var uploadManager = UploadManager()
    @State private var selectedFile: FileItem?
    @State private var showHiddenFiles = false
    @State private var fileToDelete: FileItem?
    @State private var showDeleteConfirmation = false
    @State private var isDownloading = false
    @State private var isDeleting = false
    @State private var operationError: String?
    @State private var showErrorAlert = false
    @State private var isDragOver = false

    var filteredFiles: [FileItem] {
        var files = serverManager.selectedServerFiles

        if !showHiddenFiles {
            files = files.filter { !$0.isHidden }
        }

        return files
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Path bar
                pathBar

                // File list
                if filteredFiles.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }

            // Drag overlay
            if isDragOver {
                dragOverlay
            }

            // Upload banner (non-blocking)
            if !uploadManager.items.isEmpty {
                UploadBanner(uploadManager: uploadManager) {
                    refreshFiles()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: uploadManager.items.isEmpty)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
            return true
        }
        .onAppear {
            // Load files when view appears
            if let server = serverManager.selectedServer {
                Task {
                    await serverManager.loadFiles(for: server)
                }
            }
        }
        .alert("Delete \(fileToDelete?.isDirectory == true ? "Folder" : "File")?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                fileToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let file = fileToDelete {
                    performDelete(file)
                }
            }
        } message: {
            if let file = fileToDelete {
                if file.isDirectory {
                    Text("Are you sure you want to delete the folder \"\(file.name)\" and all its contents? This cannot be undone.")
                } else {
                    Text("Are you sure you want to delete \"\(file.name)\"? This cannot be undone.")
                }
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            if let error = operationError {
                Text(error)
            }
        }
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        HStack(spacing: 8) {
            // Back button
            Button {
                navigateUp()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .disabled(isAtRoot)
            .opacity(isAtRoot ? 0.5 : 1)

            // Home button
            Button {
                navigateHome()
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }

            // Current path (clickable breadcrumbs)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                        HStack(spacing: 4) {
                            Button {
                                navigateToPathComponent(at: index)
                            } label: {
                                Text(component)
                                    .font(.system(size: 13))
                                    .foregroundColor(index == pathComponents.count - 1 ? .primary : .secondary)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovered in
                                if isHovered && index < pathComponents.count - 1 {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }

                            if index < pathComponents.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }

            Spacer()

            // Show hidden files toggle
            Toggle("Hidden", isOn: $showHiddenFiles)
                .toggleStyle(.switch)
                .controlSize(.small)

            // Upload button
            Button {
                showUploadPicker()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .help("Upload files")

            // Refresh button
            Button {
                refreshFiles()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .help("Refresh")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredFiles) { file in
                    FileRow(file: file, isSelected: selectedFile?.id == file.id) {
                        if file.isDirectory {
                            navigateTo(file.path)
                        } else {
                            selectedFile = file
                        }
                    }
                    .contextMenu {
                        if file.isDirectory {
                            Button("Open") {
                                navigateTo(file.path)
                            }
                        }

                        Button("Download") {
                            downloadFile(file)
                        }

                        Divider()

                        Button {
                            showUploadPicker()
                        } label: {
                            Label("Upload Files or Folder...", systemImage: "square.and.arrow.up")
                        }

                        Divider()

                        Button("Delete", role: .destructive) {
                            deleteFile(file)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .contextMenu {
            // Context menu for empty space / background
            Button {
                showUploadPicker()
            } label: {
                Label("Upload Files or Folder...", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button {
                refreshFiles()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Empty Directory")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)

            Text("This directory is empty.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Button {
                refreshFiles()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Computed Properties

    private var isAtRoot: Bool {
        guard let server = serverManager.selectedServer else { return true }
        return serverManager.currentPath == server.serverPath ||
               serverManager.currentPath == "/"
    }

    private var pathComponents: [String] {
        let path = serverManager.currentPath
        let components = path.split(separator: "/").map(String.init)
        if components.isEmpty {
            return ["/"]
        }
        return components
    }

    // MARK: - Actions

    private func navigateUp() {
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.navigateUp(for: server)
        }
    }

    private func navigateHome() {
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.loadFiles(for: server)
        }
    }

    private func navigateTo(_ path: String) {
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.navigateToPath(path, for: server)
        }
    }

    private func navigateToPathComponent(at index: Int) {
        // Don't navigate if clicking on the last (current) component
        guard index < pathComponents.count - 1 else { return }

        // Build the path up to and including the clicked component
        let componentsToInclude = Array(pathComponents.prefix(index + 1))
        let targetPath = "/" + componentsToInclude.joined(separator: "/")
        navigateTo(targetPath)
    }

    private func refreshFiles() {
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.loadFiles(for: server, path: serverManager.currentPath)
        }
    }

    private func downloadFile(_ file: FileItem) {
        guard let server = serverManager.selectedServer else { return }

        if file.isDirectory {
            // For directories, use folder picker
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose where to save \"\(file.name)\""
            panel.prompt = "Save Here"

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                let destinationPath = url.appendingPathComponent(file.name).path

                isDownloading = true
                Task {
                    defer { isDownloading = false }
                    let ssh = serverManager.sshService(for: server)
                    do {
                        try await ssh.downloadDirectory(remotePath: file.path, localPath: destinationPath)
                        // Open in Finder
                        NSWorkspace.shared.selectFile(destinationPath, inFileViewerRootedAtPath: url.path)
                    } catch {
                        operationError = "Failed to download folder: \(error.localizedDescription)"
                        showErrorAlert = true
                    }
                }
            }
        } else {
            // For files, use save panel
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.name
            panel.canCreateDirectories = true
            panel.message = "Choose where to save \"\(file.name)\""

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }

                isDownloading = true
                Task {
                    defer { isDownloading = false }
                    let ssh = serverManager.sshService(for: server)
                    do {
                        try await ssh.downloadFile(remotePath: file.path, localPath: url.path)
                        // Open in Finder
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    } catch {
                        operationError = "Failed to download file: \(error.localizedDescription)"
                        showErrorAlert = true
                    }
                }
            }
        }
    }

    private func deleteFile(_ file: FileItem) {
        fileToDelete = file
        showDeleteConfirmation = true
    }

    private func performDelete(_ file: FileItem) {
        guard let server = serverManager.selectedServer else { return }

        isDeleting = true
        Task {
            defer {
                isDeleting = false
                fileToDelete = nil
            }

            let ssh = serverManager.sshService(for: server)
            do {
                if file.isDirectory {
                    // Use rm -rf for directories (efficient, no file-by-file deletion)
                    try await ssh.deleteDirectory(remotePath: file.path)
                } else {
                    try await ssh.deleteFile(remotePath: file.path)
                }
                // Refresh the file list
                await serverManager.loadFiles(for: server, path: serverManager.currentPath)
            } catch {
                operationError = "Failed to delete \(file.isDirectory ? "folder" : "file"): \(error.localizedDescription)"
                showErrorAlert = true
            }
        }
    }

    // MARK: - Upload

    private func showUploadPicker() {
        guard let server = serverManager.selectedServer else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true  // Enable folder selection
        panel.allowsMultipleSelection = true
        panel.message = "Select files or folders to upload to \(serverManager.currentPath)"
        panel.prompt = "Upload"

        panel.begin { response in
            guard response == .OK, !panel.urls.isEmpty else { return }
            let ssh = serverManager.sshService(for: server)
            uploadManager.queueUpload(
                urls: panel.urls,
                remotePath: serverManager.currentPath,
                ssh: ssh
            )
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let server = serverManager.selectedServer else { return }

        // Use a lock to protect concurrent access to the urls array
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                let ssh = self.serverManager.sshService(for: server)
                self.uploadManager.queueUpload(
                    urls: urls,
                    remotePath: self.serverManager.currentPath,
                    ssh: ssh
                )
            }
        }
    }

    // MARK: - Overlays

    private var dragOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.1))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                }

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Drop files or folders to upload")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Will be uploaded to \(serverManager.currentPath)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
    }
}

// MARK: - File Row

struct FileRow: View {
    let file: FileItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // File icon
                Image(systemName: file.icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: file.iconColor))
                    .frame(width: 24)

                // File name
                Text(file.name)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // File size
                Text(file.formattedSize)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing)

                // Modified date
                Text(file.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 120, alignment: .trailing)

                // Permissions
                if let permissions = file.permissions {
                    Text(permissions)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.white.opacity(0.05) : .clear))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    FileBrowserView()
        .environmentObject(ServerManager())
        .frame(width: 800, height: 500)
        .background(Color(hex: "161618"))
}
