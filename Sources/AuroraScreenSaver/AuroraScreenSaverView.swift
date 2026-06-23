// AuroraScreenSaver — AuroraScreenSaverView
// ScreenSaverView subclass that plays the currently selected Aurora wallpaper video.
// Reads the video path from a shared JSON config in Application Support/Aurora/.
// This .saver bundle is loaded by macOS as the lock screen and idle screen animation.

import ScreenSaver
import AVFoundation
import AppKit

/// Plays the Aurora live wallpaper video as a macOS screen saver.
/// macOS Sonoma+ displays the active screen saver on the lock screen,
/// making this the bridge to live wallpapers on the lock screen.
class AuroraScreenSaverView: ScreenSaverView {

    // MARK: - Properties

    /// The AVPlayer instance for video playback.
    private var player: AVPlayer?

    /// The AVPlayerLayer rendering the video.
    private var playerLayer: AVPlayerLayer?

    /// Observer for video end (to loop).
    private var endObserver: NSObjectProtocol?

    /// Whether the video has been set up.
    private var isVideoSetup: Bool = false

    /// Gradient layer shown as fallback when no video is available.
    private var gradientLayer: CAGradientLayer?

    // MARK: - Config

    /// Shared config file location — must match ScreenSaverManager in the Aurora app.
    private static var configURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Aurora", isDirectory: true)
            .appendingPathComponent("screensaver_config.json")
    }

    /// Config model matching what Aurora writes.
    private struct ScreenSaverConfig: Codable {
        let videoPath: String
        let isLooping: Bool
        let volume: Float
        let playbackSpeed: Float
    }

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // We manage our own drawing via layers
        wantsLayer = true
        animationTimeInterval = 1.0 / 30.0
    }

    // MARK: - ScreenSaverView Lifecycle

    override func startAnimation() {
        super.startAnimation()
        setupVideoIfNeeded()
    }

    override func stopAnimation() {
        super.stopAnimation()
        tearDownVideo()
    }

    override func animateOneFrame() {
        // AVPlayer handles its own rendering on its layer;
        // nothing to do per-frame.
    }

    override func draw(_ rect: NSRect) {
        // Fill black behind the video layer
        NSColor.black.setFill()
        rect.fill()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    // MARK: - Video Setup

    private func setupVideoIfNeeded() {
        guard !isVideoSetup else { return }
        isVideoSetup = true

        guard let config = loadConfig(),
              FileManager.default.fileExists(atPath: config.videoPath) else {
            showFallbackGradient()
            return
        }

        let url = URL(fileURLWithPath: config.videoPath)

        // Create player
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2.0

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.isMuted = true  // Lock screen should be silent
        avPlayer.volume = config.volume
        self.player = avPlayer

        // Create player layer
        let layer = AVPlayerLayer(player: avPlayer)
        layer.videoGravity = .resizeAspectFill
        layer.frame = self.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Disable implicit animations for smooth resizing
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]

        self.layer?.addSublayer(layer)
        self.playerLayer = layer

        // Setup looping
        if config.isLooping {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.player?.seek(to: .zero)
                self?.player?.play()
            }
        }

        // Start playback
        avPlayer.rate = config.playbackSpeed
        avPlayer.play()
    }

    private func tearDownVideo() {
        // Stop playback
        player?.pause()

        // Remove end observer
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }

        // Remove layers
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        // Release player
        player?.replaceCurrentItem(with: nil)
        player = nil

        // Remove fallback gradient
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil

        isVideoSetup = false
    }

    // MARK: - Config Loading

    private func loadConfig() -> ScreenSaverConfig? {
        let url = AuroraScreenSaverView.configURL

        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(ScreenSaverConfig.self, from: data)
    }

    // MARK: - Fallback

    /// Shows a subtle animated dark gradient when no video is configured.
    private func showFallbackGradient() {
        let gradient = CAGradientLayer()
        gradient.frame = self.bounds
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        gradient.colors = [
            NSColor(red: 0.05, green: 0.0, blue: 0.15, alpha: 1.0).cgColor,
            NSColor(red: 0.0, green: 0.05, blue: 0.1, alpha: 1.0).cgColor,
            NSColor.black.cgColor
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)

        self.layer?.addSublayer(gradient)
        self.gradientLayer = gradient
    }

    // MARK: - Layout

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        playerLayer?.frame = self.bounds
        gradientLayer?.frame = self.bounds
    }
}
