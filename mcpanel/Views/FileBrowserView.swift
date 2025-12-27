//
//  FileBrowserView.swift
//  MCPanel
//
//  Native file browser for server files
//

import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var selectedFile: FileItem?
    @State private var showHiddenFiles = false

    var filteredFiles: [FileItem] {
        var files = serverManager.selectedServerFiles

        if !showHiddenFiles {
            files = files.filter { !$0.isHidden }
        }

        return files
    }

    var body: some View {
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
        .onAppear {
            // Load files when view appears
            if let server = serverManager.selectedServer {
                Task {
                    await serverManager.loadFiles(for: server)
                }
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

            // Current path
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(pathComponents, id: \.self) { component in
                        HStack(spacing: 4) {
                            Text(component)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)

                            if component != pathComponents.last {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
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

                        Button("Delete", role: .destructive) {
                            deleteFile(file)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
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

    private func refreshFiles() {
        guard let server = serverManager.selectedServer else { return }
        Task {
            await serverManager.loadFiles(for: server, path: serverManager.currentPath)
        }
    }

    private func downloadFile(_ file: FileItem) {
        // TODO: Implement file download
    }

    private func deleteFile(_ file: FileItem) {
        // TODO: Implement file deletion with confirmation
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
