// Aurora — Wallpaper Model
// Data model representing a single wallpaper in the library.

import Foundation

/// Supported wallpaper file formats.
enum WallpaperFormat: String, Codable, CaseIterable {
    case mp4
    case mov

    /// Returns the format for a given file extension.
    static func from(extension ext: String) -> WallpaperFormat? {
        return WallpaperFormat(rawValue: ext.lowercased())
    }

    /// Supported file extensions for import.
    static var supportedExtensions: [String] {
        return allCases.map { $0.rawValue }
    }
}

/// Represents a single wallpaper stored in the library.
struct Wallpaper: Codable, Identifiable, Equatable {

    /// Unique identifier.
    let id: UUID

    /// Display name (derived from filename or user-set).
    var name: String

    /// Absolute path to the video file.
    var filePath: String

    /// Absolute path to the generated thumbnail image (JPEG).
    var thumbnailPath: String?

    /// File format.
    let format: WallpaperFormat

    /// Video resolution as a string (e.g., "1920x1080").
    var resolution: String?

    /// Video duration in seconds.
    var duration: Double?

    /// Date the wallpaper was imported.
    let dateAdded: Date

    /// Per-wallpaper playback settings.
    var playbackSettings: PlaybackSettings

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        filePath: String,
        thumbnailPath: String? = nil,
        format: WallpaperFormat,
        resolution: String? = nil,
        duration: Double? = nil,
        dateAdded: Date = Date(),
        playbackSettings: PlaybackSettings = .default
    ) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.format = format
        self.resolution = resolution
        self.duration = duration
        self.dateAdded = dateAdded
        self.playbackSettings = playbackSettings
    }

    /// Whether the wallpaper file still exists on disk.
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: filePath)
    }
}
