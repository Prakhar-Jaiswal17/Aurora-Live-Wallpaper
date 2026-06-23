// Aurora — AuroraSettings
// App-wide settings backed by UserDefaults.

import Foundation

/// Global application settings persisted via UserDefaults.
final class AuroraSettings {

    // MARK: - Singleton

    static let shared = AuroraSettings()

    // MARK: - Keys

    private enum Keys {
        static let pauseOnBattery = "aurora.pauseOnBattery"
        static let batteryMode = "aurora.batteryMode"
        static let pauseOnFullscreen = "aurora.pauseOnFullscreen"
        static let cpuThreshold = "aurora.cpuThreshold"
        static let launchAtLogin = "aurora.launchAtLogin"
        static let defaultPlaybackSettings = "aurora.defaultPlaybackSettings"
        static let restoreLastSession = "aurora.restoreLastSession"
        static let backgroundBehavior = "aurora.backgroundBehavior"
        static let backgroundFramerate = "aurora.backgroundFramerate"
        static let cycleEnabled = "aurora.cycleEnabled"
        static let cycleInterval = "aurora.cycleInterval"
        static let cycleUnit = "aurora.cycleUnit"
        static let hasCompletedFirstLaunch = "aurora.hasCompletedFirstLaunch"
    }

    // MARK: - UserDefaults

    private let defaults = UserDefaults.standard

    // MARK: - Init

    private init() {
        registerDefaults()
    }

    /// Registers default values for all settings.
    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.pauseOnBattery: true,
            Keys.batteryMode: BatteryMode.balanced.rawValue,
            Keys.pauseOnFullscreen: true,
            Keys.cpuThreshold: 80.0,
            Keys.launchAtLogin: false,
            Keys.restoreLastSession: true,
            Keys.cycleEnabled: false,
            Keys.cycleInterval: 30.0,
            Keys.cycleUnit: CycleUnit.minutes.rawValue
        ])
    }

    // MARK: - Battery

    /// Whether to apply battery-saving behavior when on battery power.
    var pauseOnBattery: Bool {
        get { defaults.bool(forKey: Keys.pauseOnBattery) }
        set { defaults.set(newValue, forKey: Keys.pauseOnBattery) }
    }

    /// Battery saving aggressiveness level.
    var batteryMode: BatteryMode {
        get {
            let rawValue = defaults.string(forKey: Keys.batteryMode) ?? BatteryMode.balanced.rawValue
            return BatteryMode(rawValue: rawValue) ?? .balanced
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.batteryMode) }
    }

    // MARK: - Performance

    /// Whether to pause wallpapers when a fullscreen app is detected.
    var pauseOnFullscreen: Bool {
        get { defaults.bool(forKey: Keys.pauseOnFullscreen) }
        set { defaults.set(newValue, forKey: Keys.pauseOnFullscreen) }
    }

    /// CPU usage threshold (0-100) above which wallpapers are throttled.
    var cpuThreshold: Double {
        get { defaults.double(forKey: Keys.cpuThreshold) }
        set { defaults.set(min(max(newValue, 0), 100), forKey: Keys.cpuThreshold) }
    }

    // MARK: - General

    /// Whether to launch Aurora automatically at login.
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            updateLoginItem(enabled: newValue)
        }
    }

    /// Whether to restore the last session's wallpapers on app launch.
    var restoreLastSession: Bool {
        get { defaults.bool(forKey: Keys.restoreLastSession) }
        set { defaults.set(newValue, forKey: Keys.restoreLastSession) }
    }

    // MARK: - First Launch

    /// Whether the app has completed its first-launch setup (auto-import default wallpaper).
    var hasCompletedFirstLaunch: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedFirstLaunch) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedFirstLaunch) }
    }

    // MARK: - Background App Focus

    /// Behavior when working in another window (i.e., Aurora/Finder is not focused).
    var backgroundBehavior: BackgroundBehavior {
        get {
            let rawValue = defaults.string(forKey: Keys.backgroundBehavior) ?? BackgroundBehavior.keepPlaying.rawValue
            return BackgroundBehavior(rawValue: rawValue) ?? .keepPlaying
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.backgroundBehavior) }
    }

    /// Desired framerate (refresh rate) when backgroundBehavior == .lowerFramerate.
    var backgroundFramerate: Int {
        get { defaults.integer(forKey: Keys.backgroundFramerate) == 0 ? 15 : defaults.integer(forKey: Keys.backgroundFramerate) }
        set { defaults.set(max(1, min(60, newValue)), forKey: Keys.backgroundFramerate) }
    }

    // MARK: - Wallpaper Cycling

    /// Whether wallpaper cycling is enabled.
    var cycleEnabled: Bool {
        get { defaults.bool(forKey: Keys.cycleEnabled) }
        set {
            defaults.set(newValue, forKey: Keys.cycleEnabled)
            NotificationCenter.default.post(name: .cycleSettingsChanged, object: nil)
        }
    }

    /// Cycle interval value (decimal number, interpreted with cycleUnit).
    var cycleInterval: Double {
        get {
            let val = defaults.double(forKey: Keys.cycleInterval)
            return val > 0 ? val : 30.0
        }
        set {
            defaults.set(max(0.1, newValue), forKey: Keys.cycleInterval)
            NotificationCenter.default.post(name: .cycleSettingsChanged, object: nil)
        }
    }

    /// Unit for the cycle interval.
    var cycleUnit: CycleUnit {
        get {
            let rawValue = defaults.string(forKey: Keys.cycleUnit) ?? CycleUnit.minutes.rawValue
            return CycleUnit(rawValue: rawValue) ?? .minutes
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.cycleUnit)
            NotificationCenter.default.post(name: .cycleSettingsChanged, object: nil)
        }
    }

    /// Computed cycle interval in seconds.
    var cycleIntervalSeconds: TimeInterval {
        let base = cycleInterval
        switch cycleUnit {
        case .minutes: return base * 60.0
        case .hours:   return base * 3600.0
        case .days:    return base * 86400.0
        }
    }

    // MARK: - Default Playback Settings


    /// Default playback settings applied to newly imported wallpapers.
    var defaultPlaybackSettings: PlaybackSettings {
        get {
            guard let data = defaults.data(forKey: Keys.defaultPlaybackSettings),
                  let settings = try? JSONDecoder().decode(PlaybackSettings.self, from: data) else {
                return .default
            }
            return settings
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.defaultPlaybackSettings)
            }
        }
    }

    // MARK: - Launch at Login

    /// Updates the login item registration.
    private func updateLoginItem(enabled: Bool) {
        // On macOS 13+, use SMAppService for login items
        if #available(macOS 13.0, *) {
            // Note: Requires proper setup in the app bundle. For development,
            // this is a no-op. In production, use SMAppService.mainApp.register().
            AuroraLogger.system.info("Launch at login set to \(enabled)")
        }
    }
}

// MARK: - Battery Mode

/// Battery saving aggressiveness levels.
enum BatteryMode: String, Codable, CaseIterable {
    /// Pause wallpaper completely when on battery.
    case aggressive

    /// Reduce playback rate to 0.5x when on battery.
    case balanced

    /// Continue normal playback on battery (user's choice).
    case permissive

    /// Human-readable description.
    var description: String {
        switch self {
        case .aggressive: return "Pause (saves most battery)"
        case .balanced: return "Slow down (balanced)"
        case .permissive: return "Keep playing (uses more battery)"
        }
    }
}

// MARK: - Background Behavior

/// Rules for what happens when Aurora/Finder is not the focused app.
enum BackgroundBehavior: String, Codable, CaseIterable {
    /// Continue playing normally.
    case keepPlaying
    
    /// Lower the framerate to the configured backgroundFramerate.
    case lowerFramerate
    
    /// Pause completely.
    case pause
    
    var description: String {
        switch self {
        case .keepPlaying: return "Keep playing normally"
        case .lowerFramerate: return "Lower framerate"
        case .pause: return "Pause wallpaper"
        }
    }
}

// MARK: - Cycle Unit

/// Time unit for wallpaper cycling interval.
enum CycleUnit: String, Codable, CaseIterable {
    case minutes
    case hours
    case days

    var displayName: String {
        switch self {
        case .minutes: return "Minutes"
        case .hours:   return "Hours"
        case .days:    return "Days"
        }
    }
}

// MARK: - Wallpaper Target

/// Specifies where to apply a wallpaper.
enum WallpaperTarget: String, Codable, CaseIterable {
    /// Apply to both desktop (live video) and lock screen (screen saver).
    case both

    /// Apply only to the desktop (live video wallpaper).
    case homeScreen

    /// Apply only to the lock screen (via companion screen saver).
    case lockScreen

    var description: String {
        switch self {
        case .both:       return "Desktop & Lock Screen"
        case .homeScreen: return "Desktop Only"
        case .lockScreen: return "Lock Screen Only"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let cycleSettingsChanged = Notification.Name("aurora.cycleSettingsChanged")
    static let wallpaperPauseStateChanged = Notification.Name("aurora.wallpaperPauseStateChanged")
    static let wallpaperMuteStateChanged = Notification.Name("aurora.wallpaperMuteStateChanged")
}
