//
//  UploadBanner.swift
//  MCPanel
//
//  Non-blocking upload progress banner
//

import SwiftUI

struct UploadBanner: View {
    @ObservedObject var uploadManager: UploadManager
    var onRefresh: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Main banner
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 32, height: 32)

                    if uploadManager.isUploading {
                        // Animated upload arrow
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(statusColor)
                            .symbolEffect(.pulse)
                    } else if uploadManager.isComplete {
                        Image(systemName: uploadManager.failedCount > 0 ? "exclamationmark.triangle.fill" : "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(statusColor)
                    }
                }

                // Progress info
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    if uploadManager.isUploading, let fileName = uploadManager.currentFileName {
                        Text(fileName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Progress text
                if uploadManager.isUploading {
                    Text("\(uploadManager.uploadedBytes.formattedBytes) / \(uploadManager.totalBytes.formattedBytes)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Expand/collapse button (only when uploading or has multiple items)
                if uploadManager.items.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            uploadManager.isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: uploadManager.isExpanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                }

                // Cancel/Dismiss button
                Button {
                    if uploadManager.isUploading {
                        uploadManager.cancel()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            uploadManager.dismiss()
                            onRefresh()
                        }
                    }
                } label: {
                    Image(systemName: uploadManager.isUploading ? "xmark" : "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(uploadManager.isUploading ? .secondary : .white)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .background {
                    if !uploadManager.isUploading {
                        Circle()
                            .fill(Color.green.opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.white.opacity(0.1))

                    // Progress
                    Rectangle()
                        .fill(statusColor)
                        .frame(width: geometry.size.width * uploadManager.totalProgress)
                        .animation(.linear(duration: 0.1), value: uploadManager.totalProgress)
                }
            }
            .frame(height: 3)

            // Expanded file list
            if uploadManager.isExpanded {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(uploadManager.items) { item in
                            UploadItemRow(item: item)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: -8)
        .onHover { isHovered = $0 }
    }

    private var statusColor: Color {
        if uploadManager.isComplete {
            return uploadManager.failedCount > 0 ? .orange : .green
        }
        return .accentColor
    }

    private var statusText: String {
        if uploadManager.isUploading {
            return "Uploading \(uploadManager.currentItemIndex + 1) of \(uploadManager.items.count)..."
        } else if uploadManager.isComplete {
            if uploadManager.failedCount > 0 {
                return "Uploaded \(uploadManager.completedCount) files, \(uploadManager.failedCount) failed"
            } else {
                return "Uploaded \(uploadManager.completedCount) files successfully"
            }
        }
        return "Upload complete"
    }
}

// MARK: - Upload Item Row

struct UploadItemRow: View {
    let item: UploadItem

    var body: some View {
        HStack(spacing: 10) {
            // Status icon
            statusIcon
                .frame(width: 16)

            // File name
            Text(item.fileName)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            // Size / Progress
            if case .uploading = item.status {
                Text("\(item.bytesUploaded.formattedBytes) / \(item.fileSize.formattedBytes)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text(item.fileSize.formattedBytes)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background {
            if case .uploading = item.status {
                // Progress background for current item
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: geo.size.width * item.progress)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .uploading:
            ProgressView()
                .scaleEffect(0.5)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    VStack {
        Spacer()

        UploadBanner(
            uploadManager: {
                let manager = UploadManager()
                // Add some test items
                return manager
            }(),
            onRefresh: {}
        )
        .padding()
    }
    .frame(width: 500, height: 400)
    .background(Color(hex: "161618"))
}
