// Aurora — ImportHandler
// File picker (NSOpenPanel) for MP4/MOV import. Copies files to
// ~/Library/Application Support/Aurora/Wallpapers/, generates thumbnails,
// and updates the WallpaperLibrary catalog.

import AppKit
import AVFoundation

/// Handles importing wallpaper files from Finder via file picker.
final class ImportHandler {

    // MARK: - Singleton

    static let shared = ImportHandler()

    // MARK: - Init

    private init() {}

    // MARK: - Import from File Picker

    /// Shows an NSOpenPanel to let the user select video files.
    /// - Parameter completion: Called with the imported Wallpaper, or nil if cancelled.
    func importFromFilePicker(completion: @escaping (Wallpaper?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Import Wallpaper"
        panel.message = "Select a video file (MP4 or MOV) to use as a wallpaper."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .init(filenameExtension: "mp4")!,
            .init(filenameExtension: "mov")!
        ]

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }

            self?.importFile(at: url, completion: completion)
        }
    }

    // MARK: - Import File

    /// Imports a single video file into the wallpaper library.
    /// - Parameters:
    ///   - sourceURL: The source file URL.
    ///   - completion: Called with the created Wallpaper, or nil on failure.
    func importFile(at sourceURL: URL, completion: @escaping (Wallpaper?) -> Void) {
        AuroraLogger.engine.info("Importing wallpaper from: \(sourceURL.lastPathComponent, privacy: .public)")

        // Determine format
        guard let format = WallpaperFormat.from(extension: sourceURL.pathExtension) else {
            AuroraLogger.logFailure("Unsupported format: \(sourceURL.pathExtension)")
            showError("Unsupported file format. Please use MP4 or MOV.")
            completion(nil)
            return
        }

        // Generate a unique filename
        let id = UUID()
        let destFilename = "\(id.uuidString).\(sourceURL.pathExtension.lowercased())"
        let destURL = WallpaperLibrary.wallpapersDir.appendingPathComponent(destFilename)

        // Copy file to library storage
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            AuroraLogger.engine.info("Copied wallpaper to: \(destURL.path, privacy: .public)")
        } catch {
            AuroraLogger.logFailure("Failed to copy wallpaper: \(error.localizedDescription)")
            showError("Failed to import wallpaper: \(error.localizedDescription)")
            completion(nil)
            return
        }

        // Extract video metadata
        let asset = AVURLAsset(url: destURL)

        Task {
            // Get duration
            let duration: Double
            do {
                let cmDuration = try await asset.load(.duration)
                duration = CMTimeGetSeconds(cmDuration)
            } catch {
                duration = 0
            }

            // Get resolution
            let resolution: String
            do {
                let tracks = try await asset.loadTracks(withMediaType: .video)
                if let videoTrack = tracks.first {
                    let size = try await videoTrack.load(.naturalSize)
                    resolution = "\(Int(size.width))x\(Int(size.height))"
                } else {
                    resolution = "Unknown"
                }
            } catch {
                resolution = "Unknown"
            }

            // Generate thumbnail
            let thumbnailPath = await self.generateThumbnail(for: destURL, wallpaperID: id)

            // Create wallpaper model
            let wallpaper = Wallpaper(
                id: id,
                name: sourceURL.deletingPathExtension().lastPathComponent,
                filePath: destURL.path,
                thumbnailPath: thumbnailPath,
                format: format,
                resolution: resolution,
                duration: duration,
                dateAdded: Date(),
                playbackSettings: AuroraSettings.shared.defaultPlaybackSettings
            )

            // Add to library
            await MainActor.run {
                WallpaperLibrary.shared.add(wallpaper)
                AuroraLogger.engine.info(
                    "Imported '\(wallpaper.name, privacy: .public)' — \(resolution), \(String(format: "%.1f", duration))s"
                )
                completion(wallpaper)
            }
        }
    }

    // MARK: - Thumbnail Generation

    /// Generates a JPEG thumbnail from a video file.
    /// - Parameters:
    ///   - videoURL: URL of the video file.
    ///   - wallpaperID: UUID of the wallpaper for naming.
    /// - Returns: Path to the generated thumbnail, or nil on failure.
    private func generateThumbnail(for videoURL: URL, wallpaperID: UUID) async -> String? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 240)

        // Capture frame at 1 second (or 0 if video is shorter)
        let time = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: time)
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            // Save as JPEG
            let thumbFilename = "\(wallpaperID.uuidString)_thumb.jpg"
            let thumbURL = WallpaperLibrary.thumbnailsDir.appendingPathComponent(thumbFilename)

            if let tiffData = nsImage.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                try jpegData.write(to: thumbURL)
                AuroraLogger.engine.debug("Thumbnail generated: \(thumbURL.lastPathComponent, privacy: .public)")
                return thumbURL.path
            }
        } catch {
            AuroraLogger.engine.debug("Thumbnail generation failed: \(error.localizedDescription, privacy: .public)")
        }

        return nil
    }

    // MARK: - Error Display

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Import Error"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
