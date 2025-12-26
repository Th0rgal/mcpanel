//
//  VideoPlayerView.swift
//  OfflineCinema
//
//  Full-featured video player with AVKit, PiP, speed control, and subtitles
//

import SwiftUI
import AVKit
import Combine

struct VideoPlayerView: View {
    @EnvironmentObject var library: VideoLibrary
    let video: Video
    
    @StateObject private var playerController = PlayerController()
    @State private var showControls = true
    @State private var controlsTimerID: UUID? = nil
    @State private var securityScopedURL: URL? // Track URL for security-scoped access cleanup
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            // Video player
            if let player = playerController.player {
                VideoPlayerRepresentable(player: player, playerController: playerController)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControls()
                    }
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Error overlay (e.g., audio-only / unsupported video track)
            if let message = playerController.playbackErrorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)
                .transition(.opacity)
            }
            
            // Custom overlay controls
            if showControls {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .onAppear {
            setupPlayer()
            // Delay focus acquisition to ensure view is ready for keyboard input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onDisappear {
            saveProgress()
            playerController.cleanup()
            cleanupSecurityAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveProgress()
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled() // Remove blue focus ring
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
            
            Spacer()
            
            // Center play button (optional, for large tap target)
            
            Spacer()
            
            // Bottom controls
            bottomControls
        }
        .background {
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Top Bar

    @SceneStorage("sidebarVisible") private var sidebarVisible: Bool = true

    private var topBar: some View {
        HStack {
            Button {
                closePlayer()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.2)))
            }
            .buttonStyle(.plain)

            Button {
                NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.2)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(video.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // Settings menu
            Menu {
                settingsMenu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.2)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 20)
        // Move buttons down when sidebar is hidden to clear traffic lights
        .padding(.top, sidebarVisible ? 20 : 52)
        .animation(.easeInOut(duration: 0.18), value: sidebarVisible)
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 12) {
            // Progress bar
            progressBar
            
            // Control buttons
            HStack(spacing: 20) {
                // Time display
                Text(playerController.currentTimeFormatted)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 60, alignment: .leading)
                
                Spacer()
                
                // Skip backward
                Button {
                    playerController.skip(seconds: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                // Play/Pause
                Button {
                    playerController.togglePlayPause()
                } label: {
                    Image(systemName: playerController.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 50)
                }
                .buttonStyle(.plain)
                
                // Skip forward
                Button {
                    playerController.skip(seconds: 30)
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Duration
                Text(playerController.durationFormatted)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 60, alignment: .trailing)
            }
            
            // Speed and PiP controls
            HStack {
                // Speed selector
                Menu {
                    ForEach(PlaybackSpeed.allCases) { speed in
                        Button {
                            playerController.setSpeed(speed.rate)
                        } label: {
                            HStack {
                                Text(speed.label)
                                if playerController.playbackSpeed == speed.rate {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 11))
                        Text(PlaybackSpeed.labelFor(rate: playerController.playbackSpeed))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.15)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                
                Spacer()
                
                // PiP button
                if playerController.isPiPSupported {
                    Button {
                        playerController.togglePiP()
                    } label: {
                        Image(systemName: playerController.isPiPActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
                
                // Fullscreen button
                Button {
                    toggleFullscreen()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
    
    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 4)

                // Progress
                Rectangle()
                    .fill(Color(hex: "DC2626"))
                    .frame(width: geo.size.width * playerController.progress, height: 4)

                // Scrubber handle
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .position(x: geo.size.width * playerController.progress, y: 6)
                    .shadow(radius: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = max(0, min(1, value.location.x / geo.size.width))
                        playerController.seek(to: progress)
                    }
            )
            // Prevent window drag when interacting with progress bar
            .background(WindowDragBlocker())
        }
        .frame(height: 12)
    }
    
    // MARK: - Settings Menu
    
    @ViewBuilder
    private var settingsMenu: some View {
        // Subtitle tracks
        if let subtitleOptions = playerController.subtitleOptions, !subtitleOptions.isEmpty {
            Menu("Subtitles") {
                Button("Off") {
                    playerController.selectSubtitle(nil)
                }
                ForEach(subtitleOptions, id: \.self) { option in
                    Button(option.displayName) {
                        playerController.selectSubtitle(option)
                    }
                }
            }
        }
        
        // Audio tracks
        if let audioOptions = playerController.audioOptions, audioOptions.count > 1 {
            Menu("Audio Track") {
                ForEach(audioOptions, id: \.self) { option in
                    Button(option.displayName) {
                        playerController.selectAudioTrack(option)
                    }
                }
            }
        }
        
        Divider()
        
        // Speed options inline
        Menu("Playback Speed") {
            ForEach(PlaybackSpeed.allCases) { speed in
                Button {
                    playerController.setSpeed(speed.rate)
                } label: {
                    HStack {
                        Text(speed.label)
                        if playerController.playbackSpeed == speed.rate {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func setupPlayer() {
        guard let url = video.resolvedURL else { return }
        
        // Start security-scoped access and store URL for cleanup
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
        
        playerController.load(url: url)
        
        // Resume from last position if available
        // Use absolute time seek (not percentage) since duration isn't loaded yet
        if let progress = video.watchProgress, progress.position > 0, video.duration > 0 {
            let progressPercent = progress.position / video.duration
            if progressPercent < 0.95 { // Don't resume if almost finished
                playerController.seekToTime(progress.position)
            }
        }
        
        playerController.play()
        startControlsTimer()
    }
    
    private func cleanupSecurityAccess() {
        if let url = securityScopedURL {
            url.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
    }
    
    private func closePlayer() {
        saveProgress()
        library.stopPlayback()
    }
    
    private func saveProgress() {
        let currentTime = playerController.currentTime
        if currentTime > 0 {
            Task {
                await library.updateWatchProgress(for: video, position: currentTime)
            }
        }
    }
    
    private func toggleControls() {
        cancelControlsTimer()
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            startControlsTimer()
        }
    }
    
    private func startControlsTimer() {
        // Create a unique ID for this timer instance to prevent race conditions
        let timerID = UUID()
        controlsTimerID = timerID
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            
            // Only hide if THIS timer is still the active one and video is playing
            guard controlsTimerID == timerID, playerController.isPlaying else { return }
            
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = false
            }
        }
    }
    
    private func cancelControlsTimer() {
        controlsTimerID = nil
    }
    
    private func toggleFullscreen() {
        if let window = NSApplication.shared.keyWindow {
            window.toggleFullScreen(nil)
        }
    }
    
    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        switch keyPress.key {
        case .space:
            playerController.togglePlayPause()
            return .handled
        case .leftArrow:
            playerController.skip(seconds: keyPress.modifiers.contains(.command) ? -60 : -10)
            return .handled
        case .rightArrow:
            playerController.skip(seconds: keyPress.modifiers.contains(.command) ? 60 : 30)
            return .handled
        case .upArrow:
            playerController.adjustVolume(delta: 0.1)
            return .handled
        case .downArrow:
            playerController.adjustVolume(delta: -0.1)
            return .handled
        case .escape:
            closePlayer()
            return .handled
        default:
            if keyPress.characters == "f" {
                toggleFullscreen()
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Player Controller

@MainActor
class PlayerController: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackSpeed: Float = 1.0
    @Published var isPiPActive = false
    @Published var isPiPSupported = false
    @Published var playbackErrorMessage: String?
    
    /// Pending seek time for resume (set before duration is loaded)
    var pendingSeekTime: TimeInterval?
    
    @Published var subtitleOptions: [AVMediaSelectionOption]?
    @Published var audioOptions: [AVMediaSelectionOption]?
    
    private var timeObserver: Any?
    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var statusObserver: NSKeyValueObservation?
    
    /// Weak reference to AVPlayerView for PiP control (set by VideoPlayerRepresentable)
    weak var playerView: AVPlayerView?
    
    var currentTimeFormatted: String {
        formatTime(currentTime)
    }
    
    var durationFormatted: String {
        formatTime(duration)
    }
    
    func load(url: URL) {
        playbackErrorMessage = nil
        
        // Create asset with optimized loading options
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false // Faster loading for local files
        ])
        
        let playerItem = AVPlayerItem(asset: asset)
        
        // Buffer optimization for local files
        playerItem.preferredForwardBufferDuration = 5.0 // 5 seconds ahead
        
        player = AVPlayer(playerItem: playerItem)
        
        // Performance settings
        player?.allowsExternalPlayback = false // Prevent AirPlay hijacking
        player?.automaticallyWaitsToMinimizeStalling = false // Local files don't need stall prevention
        player?.preventsDisplaySleepDuringVideoPlayback = true
        
        // Observe status to surface errors like "audio plays but no video / can't decode".
        statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .failed:
                    self.playbackErrorMessage = item.error?.localizedDescription ?? "Playback failed."
                case .readyToPlay:
                    // If the asset has no video tracks, explain clearly.
                    do {
                        let tracks = try await asset.loadTracks(withMediaType: .video)
                        if tracks.isEmpty {
                            self.playbackErrorMessage = "This file has no decodable video track (audio may still play). Try an MP4/MOV with H.264 or HEVC video."
                        }
                    } catch {
                        // Ignore; if track loading fails, the player item will likely fail anyway.
                        break
                    }
                default:
                    break
                }
            }
        }
        
        // Setup time observer
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                if self.duration > 0 {
                    self.progress = self.currentTime / self.duration
                }
            }
        }
        
        // Get duration
        Task {
            if let duration = try? await player?.currentItem?.asset.load(.duration) {
                self.duration = CMTimeGetSeconds(duration)
                
                // Update progress if we had a pending seek (for resume)
                if let seekTime = self.pendingSeekTime, self.duration > 0 {
                    self.progress = seekTime / self.duration
                    self.pendingSeekTime = nil
                }
            }
            
            // Load media selection options
            await loadMediaOptions()
        }
        
        // Setup PiP (needs to be done with a player layer)
        setupPiP()
    }
    
    private func loadMediaOptions() async {
        guard let asset = player?.currentItem?.asset else { return }
        
        do {
            // Load subtitle options
            if let subtitleGroup = try await asset.loadMediaSelectionGroup(for: .legible) {
                subtitleOptions = subtitleGroup.options
            }
            
            // Load audio options
            if let audioGroup = try await asset.loadMediaSelectionGroup(for: .audible) {
                audioOptions = audioGroup.options
            }
        } catch {
            print("Failed to load media options: \(error)")
        }
    }
    
    func play() {
        player?.play()
        player?.rate = playbackSpeed
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to progress: Double) {
        guard duration > 0 else { return }
        let targetTime = CMTime(seconds: duration * progress, preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        self.progress = progress
        currentTime = duration * progress
    }
    
    /// Seek to an absolute time position (used for resume before duration is loaded)
    func seekToTime(_ seconds: TimeInterval) {
        pendingSeekTime = seconds
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }
    
    func skip(seconds: Double) {
        let newTime: Double
        if duration > 0 {
            // Duration loaded - clamp to valid range
            newTime = max(0, min(duration, currentTime + seconds))
        } else {
            // Duration not yet loaded - only prevent negative time
            newTime = max(0, currentTime + seconds)
        }
        
        let targetTime = CMTime(seconds: newTime, preferredTimescale: 600)
        player?.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
        
        // Update time display immediately (don't wait for time observer)
        currentTime = newTime
        if duration > 0 {
            progress = newTime / duration
        }
    }
    
    func setSpeed(_ rate: Float) {
        playbackSpeed = rate
        if isPlaying {
            player?.rate = rate
        }
    }
    
    func adjustVolume(delta: Float) {
        guard let player = player else { return }
        player.volume = max(0, min(1, player.volume + delta))
    }
    
    func selectSubtitle(_ option: AVMediaSelectionOption?) {
        guard let asset = player?.currentItem?.asset else { return }
        Task {
            if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
                player?.currentItem?.select(option, in: group)
            }
        }
    }
    
    func selectAudioTrack(_ option: AVMediaSelectionOption) {
        guard let asset = player?.currentItem?.asset else { return }
        Task {
            if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
                player?.currentItem?.select(option, in: group)
            }
        }
    }
    
    private func setupPiP() {
        isPiPSupported = AVPictureInPictureController.isPictureInPictureSupported()
    }
    
    func togglePiP() {
        guard let playerView = playerView else { return }
        
        // AVPlayerView on macOS provides PiP through its internal picture-in-picture controller
        // We access it via the pictureInPictureController property (available on AVPlayerView)
        if #available(macOS 12.0, *) {
            // Try to get the PiP controller from AVPlayerView
            // AVPlayerView.allowsPictureInPicturePlayback must be true (set in VideoPlayerRepresentable)
            if let pipController = playerView.value(forKey: "pictureInPictureController") as? AVPictureInPictureController {
                if pipController.isPictureInPictureActive {
                    pipController.stopPictureInPicture()
                    isPiPActive = false
                } else if pipController.isPictureInPicturePossible {
                    pipController.startPictureInPicture()
                    isPiPActive = true
                }
            }
        }
    }
    
    /// Called by VideoPlayerRepresentable when the player view is created
    func setPlayerView(_ view: AVPlayerView) {
        playerView = view
        
        // Observe PiP state changes from AVPlayerView's controller
        if #available(macOS 12.0, *) {
            if let pipController = view.value(forKey: "pictureInPictureController") as? AVPictureInPictureController {
                self.pipController = pipController
                // PiP controller will manage its own state; we just need to sync our UI
            }
        }
    }
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        statusObserver?.invalidate()
        statusObserver = nil
        player?.pause()
        player = nil
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Video Player Representable

struct VideoPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer
    let playerController: PlayerController
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none // We use custom controls
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = true
        playerView.videoGravity = .resizeAspect
        playerView.focusRingType = .none // Remove blue focus ring border
        
        // Performance optimizations
        playerView.wantsLayer = true
        playerView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        playerView.canDrawSubviewsIntoLayer = true // Flatten view hierarchy for GPU
        
        // Optimize layer for video content
        if let layer = playerView.layer {
            layer.drawsAsynchronously = true
            layer.shouldRasterize = false // Don't rasterize video content
            layer.isOpaque = true
        }
        
        // Give the controller a reference to the player view for PiP
        DispatchQueue.main.async {
            playerController.setPlayerView(playerView)
        }
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Only update player if it changed (avoid unnecessary work)
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - Playback Speed

enum PlaybackSpeed: Float, CaseIterable, Identifiable {
    case half = 0.5
    case threequarters = 0.75
    case normal = 1.0
    case oneandquarter = 1.25
    case oneandhalf = 1.5
    case double = 2.0
    
    var id: Float { rawValue }
    
    var rate: Float { rawValue }
    
    var label: String {
        switch self {
        case .half: return "0.5×"
        case .threequarters: return "0.75×"
        case .normal: return "1×"
        case .oneandquarter: return "1.25×"
        case .oneandhalf: return "1.5×"
        case .double: return "2×"
        }
    }
    
    static func labelFor(rate: Float) -> String {
        if let speed = PlaybackSpeed(rawValue: rate) {
            return speed.label
        }
        return String(format: "%.1f×", rate)
    }
}

// MARK: - Window Drag Blocker

/// An NSView that prevents window dragging when placed as a background.
/// Used on interactive controls (like the progress bar) to stop `isMovableByWindowBackground` from interfering.
private struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

