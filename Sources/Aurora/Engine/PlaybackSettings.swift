// Aurora — PlaybackSettings
// Per-wallpaper playback configuration: loop, mute, speed, volume.

import Foundation

/// Codable settings for wallpaper playback behavior.
struct PlaybackSettings: Codable, Equatable {

    /// Whether the wallpaper loops continuously. Default: true.
    var isLooping: Bool = true

    /// Whether audio is muted. Default: true (wallpapers are silent by default).
    var isMuted: Bool = true

    /// Playback speed multiplier (0.25x – 4.0x). Default: 1.0.
    var playbackSpeed: Float = 1.0 {
        didSet {
            playbackSpeed = min(max(playbackSpeed, 0.25), 4.0)
        }
    }

    /// Audio volume (0.0 – 1.0). Only relevant when not muted. Default: 0.5.
    var volume: Float = 0.5 {
        didSet {
            volume = min(max(volume, 0.0), 1.0)
        }
    }

    /// Default settings for new wallpapers.
    static let `default` = PlaybackSettings()
}
