// Aurora — VideoPlayerEngine
// AVPlayer-based video renderer with hardware acceleration, seamless looping,
// and explicit memory cleanup. Supports MP4/MOV up to 1080p.

import AppKit
import AVFoundation
import QuartzCore

/// Manages video playback for a single wallpaper using AVPlayer + AVPlayerLooper.
/// Hardware-accelerated on Apple Silicon. Max resolution: 1080p.
final class VideoPlayerEngine {

    // MARK: - Properties

    /// The AVQueuePlayer used for looped playback.
    private(set) var player: AVQueuePlayer?

    /// The AVPlayerLooper managing seamless loop transitions.
    private var looper: AVPlayerLooper?

    /// The CALayer rendering the video output.
    private(set) var playerLayer: AVPlayerLayer?

    /// Current playback settings.
    private(set) var settings: PlaybackSettings

    /// Whether the engine is currently playing.
    private(set) var isPlaying: Bool = false

    /// KVO observation for player item status.
    private var statusObservation: NSKeyValueObservation?

    /// KVO observation for player time control status.
    private var timeControlObservation: NSKeyValueObservation?

    /// The URL of the currently loaded video.
    private(set) var currentURL: URL?

    /// The source video's nominal frame rate (detected from track metadata).
    private var sourceFrameRate: Float = 30.0

    /// Whether the engine is currently framerate-throttled.
    private(set) var isFramerateThrottled: Bool = false

    /// The rate to use when framerate throttling is active.
    private var throttledRate: Float = 1.0

    // MARK: - Init

    init(settings: PlaybackSettings = .default) {
        self.settings = settings
    }

    deinit {
        cleanup()
    }

    // MARK: - Loading

    /// Loads a video file and prepares it for playback.
    /// - Parameters:
    ///   - url: URL to the video file (MP4 or MOV).
    ///   - targetLayer: The CALayer to attach the player layer to.
    ///   - completion: Called when the video is ready to play, or with an error.
    func loadVideo(url: URL, into targetLayer: CALayer, completion: ((Error?) -> Void)? = nil) {
        // Clean up any existing playback first (memory leak prevention)
        cleanup()

        currentURL = url
        AuroraLogger.engine.info("Loading video: \(url.lastPathComponent, privacy: .public)")

        // Create the asset
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        // Create an EMPTY queue player — AVPlayerLooper must manage items itself
        let queuePlayer = AVQueuePlayer()
        self.player = queuePlayer

        // Create the template item for the looper
        let templateItem = AVPlayerItem(asset: asset)
        templateItem.preferredForwardBufferDuration = 2.0

        if settings.isLooping {
            // AVPlayerLooper manages all item insertion — player MUST start empty
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)
        } else {
            // No looping — manually insert a single item
            queuePlayer.insert(templateItem, after: nil)
        }

        // Detect source frame rate from the video track
        Task {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = tracks.first {
                    let nominalRate = try await videoTrack.load(.nominalFrameRate)
                    if nominalRate > 0 {
                        await MainActor.run {
                            self.sourceFrameRate = nominalRate
                            AuroraLogger.engine.info("Detected source frame rate: \(nominalRate) FPS")
                        }
                    }
                }
            } catch {
                AuroraLogger.engine.debug("Could not detect source frame rate: \(error.localizedDescription)")
            }
        }

        // Create and configure the player layer
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill
        layer.frame = targetLayer.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Disable implicit animations on the layer for smoother rendering
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]

        self.playerLayer = layer

        // Apply current settings
        applySettings()

        // Observe the PLAYER's currentItem status (not a detached item)
        // The looper creates its own items, so we observe via the player
        statusObservation = queuePlayer.observe(\.currentItem?.status, options: [.new]) { player, _ in
            DispatchQueue.main.async {
                guard let currentItem = player.currentItem else { return }
                switch currentItem.status {
                case .readyToPlay:
                    AuroraLogger.engine.info("Video ready to play: \(url.lastPathComponent, privacy: .public)")
                    completion?(nil)
                case .failed:
                    let error = currentItem.error
                    AuroraLogger.logFailure("Video failed to load: \(error?.localizedDescription ?? "unknown")")
                    completion?(error)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        // Observe time control status for logging
        timeControlObservation = queuePlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            switch player.timeControlStatus {
            case .playing:
                self.isPlaying = true
            case .paused:
                self.isPlaying = false
            case .waitingToPlayAtSpecifiedRate:
                AuroraLogger.engine.debug("Player waiting to play at specified rate")
            @unknown default:
                break
            }
        }

        // Attach to the target layer
        targetLayer.addSublayer(layer)

        // Auto-play immediately — don't wait for readyToPlay KVO
        // AVPlayer will buffer and start when ready
        queuePlayer.play()
        queuePlayer.rate = settings.playbackSpeed
        isPlaying = true

        AuroraLogger.engine.info("Video engine configured and playing: \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Playback Control

    /// Starts or resumes video playback.
    func play() {
        guard let player = player else { return }
        player.play()
        if isFramerateThrottled {
            player.rate = throttledRate
        } else {
            player.rate = settings.playbackSpeed
        }
        isPlaying = true
        AuroraLogger.engine.debug("Playback started (rate: \(player.rate))")
    }

    /// Pauses video playback.
    func pause() {
        player?.pause()
        isPlaying = false
        AuroraLogger.engine.debug("Playback paused")
    }

    /// Toggles between play and pause.
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    // MARK: - Settings

    /// Updates playback settings and applies them immediately.
    func updateSettings(_ newSettings: PlaybackSettings) {
        self.settings = newSettings
        applySettings()
    }

    /// Applies current settings to the player.
    private func applySettings() {
        guard let player = player else { return }

        // Mute / Volume
        player.isMuted = settings.isMuted
        player.volume = settings.volume

        // Playback speed (only apply if currently playing and not framerate-throttled)
        if isPlaying && !isFramerateThrottled {
            player.rate = settings.playbackSpeed
        }

        AuroraLogger.engine.debug(
            "Settings applied — muted: \(self.settings.isMuted), speed: \(self.settings.playbackSpeed), volume: \(self.settings.volume)"
        )
    }

    /// Adjusts playback rate for power-saving throttling.
    /// This is separate from user-configured playbackSpeed.
    /// - Parameter rate: The throttled rate (e.g., 0.5 for balanced battery mode).
    func setThrottledRate(_ rate: Float) {
        guard let player = player, isPlaying else { return }
        player.rate = rate
        AuroraLogger.logPerformanceAction("Throttled playback rate to \(rate)")
    }

    /// Restores the user-configured playback rate after throttling.
    func restoreNormalRate() {
        guard let player = player, isPlaying else { return }
        if isFramerateThrottled {
            player.rate = throttledRate
        } else {
            player.rate = settings.playbackSpeed
        }
        AuroraLogger.logPerformanceAction("Restored playback rate to \(player.rate)")
    }

    /// Adjusts the playback rate to achieve a target framerate.
    /// Uses rate reduction to lower rendering load — reliable with AVPlayerLooper.
    /// - Parameter fps: Target FPS, or nil to restore normal playback.
    func setFramerateTarget(_ fps: Int?) {
        guard let player = player else { return }

        if let fps = fps {
            // Calculate rate ratio: targetFPS / sourceFrameRate
            // Clamp to 1.0 max (can't exceed native rate)
            let targetRate = min(Float(fps) / sourceFrameRate, 1.0)
            // Floor to a minimum of 0.1 to avoid near-zero rates
            let clampedRate = max(targetRate, 0.1)

            isFramerateThrottled = true
            throttledRate = clampedRate

            if isPlaying {
                player.rate = clampedRate
            }

            AuroraLogger.logPerformanceAction("Framerate throttled to ~\(fps) FPS (rate: \(clampedRate))")
        } else {
            isFramerateThrottled = false
            throttledRate = 1.0

            if isPlaying {
                player.rate = settings.playbackSpeed
            }

            AuroraLogger.logPerformanceAction("Framerate restored to normal")
        }
    }

    // MARK: - Runtime Audio Control

    /// Sets the muted state on the live player (does not persist to settings).
    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
        settings.isMuted = muted
        AuroraLogger.engine.debug("Muted set to \(muted)")
    }

    /// Sets the volume on the live player (does not persist to settings).
    func setVolume(_ volume: Float) {
        player?.volume = volume
        settings.volume = volume
        AuroraLogger.engine.debug("Volume set to \(volume)")
    }

    // MARK: - Engine Health

    /// Returns true if the video engine is healthy and capable of playback.
    /// Checks for stalled/broken AVPlayer state beyond just the window position.
    var isEngineHealthy: Bool {
        guard let player = player else { return false }

        // If we expect to be playing but the player is paused with no waiting reason, it's stalled
        if isPlaying && player.timeControlStatus == .paused && player.reasonForWaitingToPlay == nil {
            // Player thinks it's playing but AVPlayer disagrees — stalled
            AuroraLogger.engine.debug("Engine health: stalled (isPlaying=true but player is paused)")
            return false
        }

        // If the player has no current item, the looper or item was lost
        if player.currentItem == nil {
            AuroraLogger.engine.debug("Engine health: no current item")
            return false
        }

        // If the current item has failed
        if player.currentItem?.status == .failed {
            AuroraLogger.engine.debug("Engine health: current item failed")
            return false
        }

        // If the player layer is detached from its superlayer
        if playerLayer?.superlayer == nil {
            AuroraLogger.engine.debug("Engine health: player layer detached")
            return false
        }

        return true
    }

    // MARK: - Layer Management

    /// Updates the player layer frame to match a new size (e.g., screen resolution change).
    /// The frame should be in bounds-relative coordinates (origin 0,0).
    func updateLayerFrame(_ frame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Ensure origin is at (0,0) for correct layer positioning
        let boundsFrame = CGRect(origin: .zero, size: frame.size)
        playerLayer?.frame = boundsFrame
        playerLayer?.bounds = boundsFrame
        CATransaction.commit()
    }

    // MARK: - Memory Cleanup

    /// Explicitly cleans up all AVPlayer resources to prevent memory leaks.
    /// MUST be called when:
    /// - Changing wallpaper
    /// - Removing a display
    /// - App termination
    func cleanup() {
        AuroraLogger.engine.info("Cleaning up video engine for: \(self.currentURL?.lastPathComponent ?? "nil", privacy: .public)")

        // Cancel observations
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil

        // Stop playback
        player?.pause()

        // Disable looper BEFORE clearing the player item
        looper?.disableLooping()
        looper = nil

        // Clear player item to release asset references
        player?.replaceCurrentItem(with: nil)

        // Detach layer from player and remove from superlayer
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        // Release player
        player = nil

        // Reset state
        isPlaying = false
        isFramerateThrottled = false
        throttledRate = 1.0
        currentURL = nil

        AuroraLogger.engine.info("Video engine cleanup complete")
    }
}
