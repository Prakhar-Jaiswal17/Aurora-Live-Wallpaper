// Aurora — DynamicWallpaperBuilder
// Builds Apple-format dynamic wallpaper HEIC files from video frames.
// macOS natively recognizes these HEIC files as "Dynamic Desktop" wallpapers
// and displays them on BOTH the desktop AND the lock screen.
//
// Supported formats:
//   - Appearance-based (apple_desktop:apr): 2 images, switches on light/dark mode
//   - Time-based (apple_desktop:h24): N images, cycles throughout the day

import AppKit
import AVFoundation

/// Builds macOS Dynamic Desktop HEIC files from video frames.
/// These files embed Apple-proprietary XMP metadata that macOS reads
/// to display the wallpaper natively — including on the lock screen.
final class DynamicWallpaperBuilder {

    // MARK: - Duration Helper

    /// Retrieves asset duration synchronously.
    /// Uses the older synchronous API since all frame extraction is synchronous via copyCGImage.
    @available(macOS, deprecated: 13.0, message: "Using synchronous duration for synchronous frame extraction")
    private static func getAssetDuration(_ asset: AVURLAsset) -> Double {
        return CMTimeGetSeconds(asset.duration)
    }

    // MARK: - Public API

    /// Creates an appearance-based dynamic wallpaper (light + dark) from a video file.
    /// Extracts two representative frames and packages them into an Apple-format HEIC.
    /// - Parameters:
    ///   - videoURL: Path to the source video file.
    ///   - outputURL: Where to write the resulting .heic file.
    /// - Throws: If frame extraction or HEIC creation fails.
    static func createAppearanceWallpaper(from videoURL: URL, outputURL: URL) throws {
        let asset = AVURLAsset(url: videoURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let durationSeconds = getAssetDuration(asset)
        guard durationSeconds > 0 else {
            throw BuilderError.invalidVideo("Video has zero duration")
        }

        // Extract 2 frames: one from the first quarter, one from the third quarter
        let lightTime = CMTime(seconds: min(durationSeconds * 0.25, durationSeconds - 0.1), preferredTimescale: 600)
        let darkTime = CMTime(seconds: min(durationSeconds * 0.75, durationSeconds - 0.1), preferredTimescale: 600)

        var actualTime = CMTime.zero
        let lightImage = try generator.copyCGImage(at: lightTime, actualTime: &actualTime)
        let darkImage = try generator.copyCGImage(at: darkTime, actualTime: &actualTime)

        AuroraLogger.engine.info("Extracted 2 frames for appearance-based dynamic wallpaper")
        try buildAppearanceHEIC(lightImage: lightImage, darkImage: darkImage, outputURL: outputURL)
    }

    /// Creates a time-based dynamic wallpaper with multiple frames that cycle throughout the day.
    /// - Parameters:
    ///   - videoURL: Path to the source video file.
    ///   - outputURL: Where to write the resulting .heic file.
    ///   - frameCount: Number of frames to extract (default: 16, like Apple's own wallpapers).
    /// - Throws: If frame extraction or HEIC creation fails.
    static func createTimeBasedWallpaper(from videoURL: URL, outputURL: URL, frameCount: Int = 16) throws {
        let asset = AVURLAsset(url: videoURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let durationSeconds = getAssetDuration(asset)
        guard durationSeconds > 0 else {
            throw BuilderError.invalidVideo("Video has zero duration")
        }

        var images: [CGImage] = []
        for i in 0..<frameCount {
            let fraction = Double(i) / Double(frameCount)
            let seconds = min(durationSeconds * fraction, durationSeconds - 0.1)
            let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)

            var actualTime = CMTime.zero
            let image = try generator.copyCGImage(at: time, actualTime: &actualTime)
            images.append(image)
        }

        AuroraLogger.engine.info("Extracted \(frameCount) frames for time-based dynamic wallpaper")
        try buildTimeBasedHEIC(images: images, outputURL: outputURL)
    }

    /// Extracts a single high-resolution frame and saves it as a JPEG.
    /// Fallback for systems that don't support HEIC encoding.
    /// - Parameters:
    ///   - videoURL: Path to the source video file.
    ///   - outputURL: Where to write the resulting .jpg file.
    /// - Throws: If frame extraction or image saving fails.
    static func extractSingleFrame(from videoURL: URL, outputURL: URL) throws {
        let asset = AVURLAsset(url: videoURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)

        let durationSeconds = getAssetDuration(asset)
        let time = CMTime(seconds: min(max(1.0, durationSeconds * 0.25), durationSeconds - 0.1), preferredTimescale: 600)

        var actualTime = CMTime.zero
        let cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)

        // Save as JPEG
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            throw BuilderError.imageEncodingFailed("Failed to encode JPEG")
        }
        try jpegData.write(to: outputURL, options: .atomic)
        AuroraLogger.engine.info("Extracted single frame as JPEG fallback")
    }

    // MARK: - HEIC Building

    /// Builds an appearance-based dynamic desktop HEIC file.
    /// Uses `apple_desktop:apr` XMP metadata that macOS reads to switch
    /// between light and dark mode images.
    private static func buildAppearanceHEIC(lightImage: CGImage, darkImage: CGImage, outputURL: URL) throws {
        let images = [lightImage, darkImage]

        // Build the appearance metadata plist: { "l": 0, "d": 1 }
        // l = index of light-mode image, d = index of dark-mode image
        let metadata: [String: Any] = ["l": 0, "d": 1]
        let base64Metadata = try encodePlistToBase64(metadata)

        // Create HEIC image destination
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            "public.heic" as CFString,
            images.count,
            nil
        ) else {
            throw BuilderError.heicCreationFailed("Failed to create HEIC destination")
        }

        // Set HEIC encoding quality
        let imageProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]

        // Add first image with XMP metadata
        let xmpMetadata = CGImageMetadataCreateMutable()
        guard let tag = CGImageMetadataTagCreate(
            "http://ns.apple.com/namespace/1.0/" as CFString,
            "apple_desktop" as CFString,
            "apr" as CFString,
            .string,
            base64Metadata as CFString
        ) else {
            throw BuilderError.metadataCreationFailed("Failed to create appearance metadata tag")
        }

        guard CGImageMetadataSetTagWithPath(xmpMetadata, nil, "xmp:apr" as CFString, tag) else {
            throw BuilderError.metadataCreationFailed("Failed to set metadata tag path")
        }

        CGImageDestinationAddImageAndMetadata(
            destination,
            images[0],
            xmpMetadata,
            imageProperties as CFDictionary
        )

        // Add remaining images (no metadata needed)
        for i in 1..<images.count {
            CGImageDestinationAddImage(destination, images[i], imageProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw BuilderError.heicFinalizationFailed("Failed to finalize HEIC file")
        }

        AuroraLogger.engine.info("Built appearance-based dynamic wallpaper HEIC at: \(outputURL.path, privacy: .public)")
    }

    /// Builds a time-based dynamic desktop HEIC file.
    /// Uses `apple_desktop:h24` XMP metadata — macOS cycles through
    /// images throughout the 24-hour day.
    private static func buildTimeBasedHEIC(images: [CGImage], outputURL: URL) throws {
        let count = images.count
        guard count >= 2 else {
            throw BuilderError.invalidVideo("Need at least 2 images for time-based wallpaper")
        }

        // Build time items: each image mapped to a fraction of the day (0.0 = midnight, 0.5 = noon)
        var timeItems: [[String: Any]] = []
        for i in 0..<count {
            let timeFraction = Double(i) / Double(count)
            timeItems.append(["i": i, "t": timeFraction])
        }

        // Appearance fallback indices for light/dark mode static views
        let lightIndex = count / 4           // ~6 AM position
        let darkIndex = (count * 3) / 4      // ~6 PM position

        let metadata: [String: Any] = [
            "ti": timeItems,
            "ap": ["l": lightIndex, "d": darkIndex]
        ]

        let base64Metadata = try encodePlistToBase64(metadata)

        // Create HEIC image destination
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            "public.heic" as CFString,
            count,
            nil
        ) else {
            throw BuilderError.heicCreationFailed("Failed to create HEIC destination")
        }

        let imageProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85
        ]

        // Add first image with XMP metadata
        let xmpMetadata = CGImageMetadataCreateMutable()
        guard let tag = CGImageMetadataTagCreate(
            "http://ns.apple.com/namespace/1.0/" as CFString,
            "apple_desktop" as CFString,
            "h24" as CFString,
            .string,
            base64Metadata as CFString
        ) else {
            throw BuilderError.metadataCreationFailed("Failed to create time-based metadata tag")
        }

        guard CGImageMetadataSetTagWithPath(xmpMetadata, nil, "xmp:h24" as CFString, tag) else {
            throw BuilderError.metadataCreationFailed("Failed to set metadata tag path")
        }

        CGImageDestinationAddImageAndMetadata(
            destination,
            images[0],
            xmpMetadata,
            imageProperties as CFDictionary
        )

        // Add remaining images
        for i in 1..<count {
            CGImageDestinationAddImage(destination, images[i], imageProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw BuilderError.heicFinalizationFailed("Failed to finalize HEIC file")
        }

        AuroraLogger.engine.info("Built time-based dynamic wallpaper HEIC (\(count) frames) at: \(outputURL.path, privacy: .public)")
    }

    // MARK: - Helpers

    /// Encodes a property list dictionary as a Base64 string (binary plist format).
    /// This is the format Apple's dynamic wallpaper XMP metadata expects.
    private static func encodePlistToBase64(_ plist: [String: Any]) throws -> String {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        return data.base64EncodedString()
    }

    // MARK: - Errors

    enum BuilderError: LocalizedError {
        case invalidVideo(String)
        case imageEncodingFailed(String)
        case heicCreationFailed(String)
        case metadataCreationFailed(String)
        case heicFinalizationFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidVideo(let msg): return "Invalid video: \(msg)"
            case .imageEncodingFailed(let msg): return "Image encoding failed: \(msg)"
            case .heicCreationFailed(let msg): return "HEIC creation failed: \(msg)"
            case .metadataCreationFailed(let msg): return "Metadata creation failed: \(msg)"
            case .heicFinalizationFailed(let msg): return "HEIC finalization failed: \(msg)"
            }
        }
    }
}
