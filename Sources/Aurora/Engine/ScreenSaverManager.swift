// Aurora — ScreenSaverManager
// Manages the companion AuroraScreenSaver.saver bundle:
//   - Installs the .saver from the app bundle to ~/Library/Screen Savers/
//   - Sets it as the active system screensaver
//   - Writes the shared config file so the screensaver knows which video to play

import AppKit

/// Manages the Aurora companion screen saver for lock screen live wallpaper support.
/// The .saver bundle is embedded in Aurora.app/Contents/Resources/ at build time
/// and installed to ~/Library/Screen Savers/ on first launch.
final class ScreenSaverManager {

    // MARK: - Singleton

    static let shared = ScreenSaverManager()

    // MARK: - Constants

    private let saverBundleName = "AuroraScreenSaver.saver"
    private let saverIdentifier = "com.aurora.livewallpaper.screensaver"
    private let configFileName = "screensaver_config.json"

    // MARK: - Paths

    /// Where .saver bundles are installed for the current user.
    private var screenSaversDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Screen Savers", isDirectory: true)
    }

    /// The installed .saver location.
    private var installedSaverURL: URL {
        return screenSaversDir.appendingPathComponent(saverBundleName)
    }

    /// The .saver embedded in Aurora.app/Contents/Resources/.
    private var embeddedSaverURL: URL? {
        return Bundle.main.url(forResource: "AuroraScreenSaver", withExtension: "saver")
    }

    /// Shared config directory.
    private var configDir: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Aurora", isDirectory: true)
    }

    /// Shared config file URL.
    private var configURL: URL {
        return configDir.appendingPathComponent(configFileName)
    }

    // MARK: - Config Model

    /// Shared config written by Aurora, read by the screensaver.
    struct ScreenSaverConfig: Codable {
        let videoPath: String
        let isLooping: Bool
        let volume: Float
        let playbackSpeed: Float
    }

    // MARK: - Init

    private init() {}

    // MARK: - Installation

    /// Installs the .saver bundle and activates it as the system screensaver.
    /// Safe to call multiple times — only installs/updates if needed.
    func installIfNeeded() {
        guard let embeddedURL = embeddedSaverURL else {
            AuroraLogger.engine.warning("No embedded .saver bundle found in app resources — screen saver features disabled")
            return
        }

        let fm = FileManager.default

        // Create Screen Savers directory if needed
        try? fm.createDirectory(at: screenSaversDir, withIntermediateDirectories: true)

        // Check if we need to install or update
        let needsInstall: Bool
        if fm.fileExists(atPath: installedSaverURL.path) {
            // Compare versions — reinstall if the embedded version is newer
            let embeddedVersion = bundleVersion(at: embeddedURL)
            let installedVersion = bundleVersion(at: installedSaverURL)
            needsInstall = (embeddedVersion != installedVersion)

            if needsInstall {
                AuroraLogger.engine.info("Updating screen saver: \(installedVersion ?? "?") → \(embeddedVersion ?? "?")")
                try? fm.removeItem(at: installedSaverURL)
            }
        } else {
            needsInstall = true
        }

        if needsInstall {
            do {
                try fm.copyItem(at: embeddedURL, to: installedSaverURL)
                AuroraLogger.engine.info("Screen saver installed to: \(self.installedSaverURL.path, privacy: .public)")
            } catch {
                AuroraLogger.logFailure("Failed to install screen saver: \(error.localizedDescription)")
                return
            }
        }

        // Activate as the system screensaver
        activateScreenSaver()
    }

    // MARK: - Activation

    /// Sets AuroraScreenSaver as the active system screensaver.
    private func activateScreenSaver() {
        let saverPath = installedSaverURL.path

        // Ad-hoc sign the installed .saver for macOS to accept it
        let signProcess = Process()
        signProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProcess.arguments = ["--force", "--deep", "--sign", "-", saverPath]
        try? signProcess.run()
        signProcess.waitUntilExit()

        // Set screensaver via defaults (standard domain)
        let moduleDict = "{ moduleName = AuroraScreenSaver; path = \\\"\(saverPath)\\\"; type = 0; }"
        runDefaults(args: ["write", "com.apple.screensaver", "moduleDict", moduleDict])

        // Set screensaver via defaults -currentHost (ByHost domain — what macOS actually reads)
        runDefaults(args: ["-currentHost", "write", "com.apple.screensaver", "moduleDict", moduleDict])

        AuroraLogger.engine.info("AuroraScreenSaver activated as system screensaver")
    }

    /// Runs the `defaults` command with the given arguments.
    private func runDefaults(args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = args

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AuroraLogger.engine.debug("defaults command failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Config Management

    /// Updates the shared screensaver config with the current wallpaper video path.
    /// Called by WallpaperManager whenever a wallpaper is set.
    func updateConfig(videoPath: String, isLooping: Bool = true, volume: Float = 0.0, playbackSpeed: Float = 1.0) {
        let config = ScreenSaverConfig(
            videoPath: videoPath,
            isLooping: isLooping,
            volume: volume,
            playbackSpeed: playbackSpeed
        )

        let fm = FileManager.default
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
            AuroraLogger.engine.info("Screensaver config updated — video: \(videoPath, privacy: .public)")
        } catch {
            AuroraLogger.logFailure("Failed to write screensaver config: \(error.localizedDescription)")
        }
    }

    /// Clears the screensaver config (e.g., when all wallpapers are removed).
    func clearConfig() {
        try? FileManager.default.removeItem(at: configURL)
        AuroraLogger.engine.info("Screensaver config cleared")
    }

    // MARK: - Helpers

    /// Reads the bundle version from a .saver bundle's Info.plist.
    private func bundleVersion(at url: URL) -> String? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleVersion"] as? String
    }

    // MARK: - Cleanup

    /// Removes the installed screensaver and config. Called on app uninstall if needed.
    func uninstall() {
        let fm = FileManager.default
        try? fm.removeItem(at: installedSaverURL)
        try? fm.removeItem(at: configURL)
        AuroraLogger.engine.info("Screen saver uninstalled")
    }
}
