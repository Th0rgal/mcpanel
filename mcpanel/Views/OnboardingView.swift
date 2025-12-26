//
//  OnboardingView.swift
//  MCPanel
//
//  Full-screen onboarding flow for adding servers
//

import SwiftUI

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case connection = 1
    case serverDetails = 2
    case complete = 3

    var title: String {
        switch self {
        case .welcome: return "Welcome to MCPanel"
        case .connection: return "Connect to Your Server"
        case .serverDetails: return "Server Configuration"
        case .complete: return "You're All Set!"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "Manage your Minecraft servers with a beautiful native experience"
        case .connection: return "Enter your SSH connection details"
        case .serverDetails: return "Configure your Minecraft server paths"
        case .complete: return "Your server has been added successfully"
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var serverManager: ServerManager
    @Binding var isPresented: Bool

    @State private var currentStep: OnboardingStep = .welcome
    @State private var isAnimating = false
    @State private var hasInitialized = false

    // Whether this is adding a new server (skip welcome) or first-time setup
    private var isAddingServer: Bool {
        !serverManager.servers.isEmpty
    }

    // Server configuration state
    @State private var serverName = ""
    @State private var host = ""
    @State private var sshPort = "22"
    @State private var sshUsername = "root"
    @State private var identityFilePath = "~/.ssh/id_rsa"
    @State private var serverPath = "/home/minecraft"
    @State private var screenSession = ""
    @State private var systemdUnit = ""
    @State private var serverType: ServerType = .paper

    // Validation
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .untested

    enum ConnectionStatus {
        case untested
        case testing
        case success
        case failed(String)
    }

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient

            // Close button (when adding additional servers)
            if isAddingServer {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 32, height: 32)
                                .background {
                                    Circle()
                                        .fill(.white.opacity(0.1))
                                }
                        }
                        .buttonStyle(.plain)
                        .padding(24)
                    }
                    Spacer()
                }
            }

            // Content
            VStack(spacing: 0) {
                // Progress indicator
                if currentStep != .welcome {
                    progressIndicator
                        .padding(.top, 60)
                }

                Spacer()

                // Step content
                stepContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(currentStep)

                Spacer()

                // Navigation buttons
                navigationButtons
                    .padding(.bottom, 60)
            }
            .padding(.horizontal, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            // Skip welcome step when adding additional servers
            if !hasInitialized {
                hasInitialized = true
                if isAddingServer {
                    currentStep = .connection
                }
            }
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            // Base gradient - matching the main app
            LinearGradient(
                colors: [Color(hex: "17171A"), Color(hex: "121214")],
                startPoint: .top,
                endPoint: .bottom
            )

            // Top-left glow - subtle white/blue
            RadialGradient(
                colors: [
                    Color.white.opacity(0.06),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 520
            )

            // Top-right accent glow - subtle cyan
            RadialGradient(
                colors: [
                    Color(hex: "55FFFF").opacity(0.04),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 100,
                endRadius: 500
            )

            // Bottom accent glow - subtle purple
            RadialGradient(
                colors: [
                    Color(hex: "AA00AA").opacity(0.03),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 50,
                endRadius: 400
            )
        }
    }

    // Accent color for the onboarding - liquid glass style
    private let accentColor = Color(hex: "55FFFF")

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases.filter { $0 != .welcome }, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? accentColor : Color.white.opacity(0.2))
                    .frame(width: step == currentStep ? 32 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .connection:
            connectionStep
        case .serverDetails:
            serverDetailsStep
        case .complete:
            completeStep
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        VStack(spacing: 40) {
            // Icon with liquid glass effect
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)

                // Glass circle
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }

                Image(systemName: "server.rack")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .scaleEffect(isAnimating ? 1 : 0.8)
            .opacity(isAnimating ? 1 : 0)

            VStack(spacing: 16) {
                Text("Welcome to MCPanel")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Manage your Minecraft servers with a beautiful native experience.\nMonitor, control, and configure — all from one place.")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)

            // Feature highlights
            HStack(spacing: 40) {
                FeatureHighlight(icon: "terminal.fill", title: "Live Console", description: "Real-time logs & commands")
                FeatureHighlight(icon: "puzzlepiece.extension.fill", title: "Plugin Manager", description: "Enable/disable with one click")
                FeatureHighlight(icon: "folder.fill", title: "File Browser", description: "Navigate server files")
            }
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 30)
            .animation(.easeOut(duration: 0.8).delay(0.3), value: isAnimating)
        }
    }

    // MARK: - Connection Step

    private var connectionStep: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text(currentStep.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(currentStep.subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }

            // Form fields
            VStack(spacing: 20) {
                OnboardingTextField(
                    label: "Server Name",
                    placeholder: "My Minecraft Server",
                    text: $serverName,
                    icon: "tag.fill"
                )

                HStack(spacing: 16) {
                    OnboardingTextField(
                        label: "Host / IP",
                        placeholder: "mc.example.com",
                        text: $host,
                        icon: "network"
                    )

                    OnboardingTextField(
                        label: "SSH Port",
                        placeholder: "22",
                        text: $sshPort,
                        icon: "number"
                    )
                    .frame(width: 120)
                }

                HStack(spacing: 16) {
                    OnboardingTextField(
                        label: "Username",
                        placeholder: "root",
                        text: $sshUsername,
                        icon: "person.fill"
                    )

                    OnboardingTextField(
                        label: "SSH Key Path",
                        placeholder: "~/.ssh/id_rsa",
                        text: $identityFilePath,
                        icon: "key.fill"
                    )
                }

                // Connection test
                connectionTestButton
            }
            .frame(maxWidth: 600)
        }
    }

    private var connectionTestButton: some View {
        Button {
            testConnection()
        } label: {
            HStack(spacing: 10) {
                switch connectionStatus {
                case .untested:
                    Image(systemName: "bolt.fill")
                    Text("Test Connection")
                case .testing:
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing...")
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connection Successful")
                case .failed(let error):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(connectionStatusColor.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(connectionStatusColor.opacity(0.4), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(host.isEmpty || isTestingConnection)
        .padding(.top, 8)
    }

    private var connectionStatusColor: Color {
        switch connectionStatus {
        case .untested, .testing: return .white
        case .success: return .green
        case .failed: return .red
        }
    }

    // MARK: - Server Details Step

    private var serverDetailsStep: some View {
        VStack(spacing: 40) {
            VStack(spacing: 12) {
                Text(currentStep.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(currentStep.subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(spacing: 20) {
                OnboardingTextField(
                    label: "Server Path",
                    placeholder: "/home/minecraft/server",
                    text: $serverPath,
                    icon: "folder.fill"
                )

                HStack(spacing: 16) {
                    OnboardingTextField(
                        label: "Screen Session (optional)",
                        placeholder: "minecraft",
                        text: $screenSession,
                        icon: "rectangle.on.rectangle"
                    )

                    OnboardingTextField(
                        label: "Systemd Unit (optional)",
                        placeholder: "minecraft.service",
                        text: $systemdUnit,
                        icon: "gearshape.fill"
                    )
                }

                // Server type picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server Type")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    HStack(spacing: 12) {
                        ForEach(ServerType.allCases) { type in
                            ServerTypeButton(
                                type: type,
                                isSelected: serverType == type
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    serverType = type
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 600)
        }
    }

    // MARK: - Complete Step

    private var completeStep: some View {
        VStack(spacing: 40) {
            // Success animation with liquid glass
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentColor.opacity(0.15), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)

                // Glass circle
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }

                Image(systemName: "checkmark")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(accentColor)
            }

            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("\(serverName.isEmpty ? "Your server" : serverName) has been added to MCPanel.\nYou can now monitor and manage it from the dashboard.")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Server summary card
            serverSummaryCard
        }
    }

    private var serverSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: serverType.icon)
                    .font(.system(size: 20))
                    .foregroundColor(accentColor)

                Text(serverName.isEmpty ? "Minecraft Server" : serverName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text(serverType.rawValue)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(spacing: 8) {
                SummaryRow(label: "Host", value: host)
                SummaryRow(label: "Path", value: serverPath)
                if !screenSession.isEmpty {
                    SummaryRow(label: "Screen", value: screenSession)
                }
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
        .frame(maxWidth: 400)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            // Show back button: not on welcome, not on complete, and not on connection if adding server
            if currentStep != .welcome && currentStep != .complete && !(currentStep == .connection && isAddingServer) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        goToPreviousStep()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.1))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if currentStep == .complete {
                        finishOnboarding()
                    } else {
                        goToNextStep()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(nextButtonTitle)
                    if currentStep != .complete {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.5), accentColor.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                        .shadow(color: accentColor.opacity(0.2), radius: 12, y: 4)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canProceed)
            .opacity(canProceed ? 1 : 0.5)
        }
    }

    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome: return "Get Started"
        case .connection: return "Continue"
        case .serverDetails: return "Add Server"
        case .complete: return "Start Using MCPanel"
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case .welcome: return true
        case .connection: return !host.isEmpty && !sshUsername.isEmpty
        case .serverDetails: return !serverPath.isEmpty
        case .complete: return true
        }
    }

    // MARK: - Navigation Actions

    private func goToNextStep() {
        if currentStep == .serverDetails {
            // Add the server
            addServer()
        }

        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            currentStep = nextStep
        }
    }

    private func goToPreviousStep() {
        if let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) {
            currentStep = prevStep
        }
    }

    private func testConnection() {
        connectionStatus = .testing

        Task {
            let tempServer = Server(
                name: "Test",
                host: host,
                sshPort: Int(sshPort) ?? 22,
                sshUsername: sshUsername,
                identityFilePath: identityFilePath.isEmpty ? nil : identityFilePath,
                serverPath: serverPath
            )

            let ssh = SSHService(server: tempServer)

            do {
                let connected = try await ssh.testConnection()
                await MainActor.run {
                    connectionStatus = connected ? .success : .failed("Connection refused")
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func addServer() {
        let server = Server(
            name: serverName.isEmpty ? "Minecraft Server" : serverName,
            host: host,
            sshPort: Int(sshPort) ?? 22,
            sshUsername: sshUsername,
            identityFilePath: identityFilePath.isEmpty ? nil : identityFilePath,
            serverPath: serverPath,
            screenSession: screenSession.isEmpty ? nil : screenSession,
            systemdUnit: systemdUnit.isEmpty ? nil : systemdUnit,
            serverType: serverType
        )

        Task {
            await serverManager.addServer(server)
        }
    }

    private func finishOnboarding() {
        isPresented = false
    }
}

// MARK: - Supporting Views

struct FeatureHighlight: View {
    let icon: String
    let title: String
    let description: String

    private let accentColor = Color(hex: "55FFFF")

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.2), .white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

struct OnboardingTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let icon: String

    @State private var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 20)

                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(isFocused ? 0.3 : 0.1), lineWidth: 1)
                    }
            }
        }
    }
}

struct ServerTypeButton: View {
    let type: ServerType
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    private let accentColor = Color(hex: "55FFFF")

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? accentColor : .white.opacity(0.5))

                Text(type.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            }
            .frame(width: 70, height: 70)
            .background {
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isSelected ?
                                LinearGradient(
                                    colors: [accentColor.opacity(0.5), accentColor.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                            lineWidth: 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
        .environmentObject(ServerManager())
        .frame(width: 1000, height: 700)
}
