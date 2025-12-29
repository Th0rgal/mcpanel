//
//  SSHKeyPicker.swift
//  MCPanel
//
//  A file picker for SSH keys that creates security-scoped bookmarks
//  for sandbox-compatible access.
//

import SwiftUI
import AppKit

struct SSHKeyPicker: View {
    @Binding var keyPath: String
    @Binding var keyBookmark: Data?

    var body: some View {
        HStack(spacing: 8) {
            TextField("SSH Key Path", text: $keyPath)
                .textFieldStyle(.roundedBorder)
                .disabled(true)

            Button {
                selectSSHKey()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Browse for SSH key file")

            if !keyPath.isEmpty {
                Button {
                    keyPath = ""
                    keyBookmark = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear SSH key")
            }
        }
    }

    private func selectSSHKey() {
        let panel = NSOpenPanel()
        panel.title = "Select SSH Private Key"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        // Start in ~/.ssh/ if it exists
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if FileManager.default.fileExists(atPath: sshDir.path) {
            panel.directoryURL = sshDir
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            // Create security-scoped bookmark for sandbox access
            keyBookmark = Server.createSSHKeyBookmark(for: url)
            keyPath = url.path
        }
    }
}

#Preview {
    SSHKeyPicker(
        keyPath: .constant("~/.ssh/id_rsa"),
        keyBookmark: .constant(nil)
    )
    .padding()
}
