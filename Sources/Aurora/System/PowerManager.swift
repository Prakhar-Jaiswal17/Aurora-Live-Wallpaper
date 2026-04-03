// Aurora — PowerManager
// Battery/AC state monitoring with 3-tier throttling modes.
// Also handles screen lock/unlock detection — pauses on lock, resumes on unlock.

import AppKit
import IOKit.ps

/// Monitors power source state and screen lock state.
/// Applies battery-saving behavior and pauses wallpapers when screen is locked.
final class PowerManager {

    // MARK: - Singleton

    static let shared = PowerManager()

    // MARK: - Properties

    /// Current power source type.
    enum PowerSource {
        case ac
        case battery
        case unknown
    }

    /// Current power source.
    private(set) var currentPowerSource: PowerSource = .unknown

    /// Whether we're currently in a battery-saving state.
    private(set) var isBatterySaving: Bool = false

    /// Whether the screen is currently locked.
    private(set) var isScreenLocked: Bool = false

    /// Timer for periodic power checks.
    private var powerCheckTimer: Timer?

    // MARK: - Init

    private init() {
        updatePowerSource()
        startMonitoring()
        setupScreenLockObservers()
        AuroraLogger.system.info("PowerManager initialized — power source: \(String(describing: self.currentPowerSource))")
    }

    // MARK: - Monitoring

    /// Starts periodic power source monitoring.
    private func startMonitoring() {
        // Check every 5 seconds (power changes are infrequent)
        powerCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkPowerChange()
        }

        // Also observe power source change notifications via CFRunLoop
        let context = Unmanaged.passUnretained(self).toOpaque()
        let loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let manager = Unmanaged<PowerManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.checkPowerChange()
            }
        }, context).takeRetainedValue()

        CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
        AuroraLogger.system.info("Power source monitoring started")
    }

    /// Checks if the power source has changed and applies appropriate behavior.
    private func checkPowerChange() {
        let previousSource = currentPowerSource
        updatePowerSource()

        guard currentPowerSource != previousSource else { return }

        AuroraLogger.system.info("Power source changed: \(String(describing: previousSource)) → \(String(describing: self.currentPowerSource))")

        applyPowerPolicy()
    }

    /// Updates the current power source from IOKit.
    private func updatePowerSource() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let first = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, first as CFTypeRef)?.takeUnretainedValue() as? [String: Any] else {
            currentPowerSource = .unknown
            return
        }

        if let powerSourceState = info[kIOPSPowerSourceStateKey] as? String {
            currentPowerSource = (powerSourceState == kIOPSACPowerValue) ? .ac : .battery
        } else {
            currentPowerSource = .unknown
        }
    }

    // MARK: - Power Policy

    /// Applies the battery-saving policy based on current settings.
    func applyPowerPolicy() {
        let settings = AuroraSettings.shared

        guard settings.pauseOnBattery else {
            // Battery optimization disabled by user
            if isBatterySaving {
                restoreFromBatterySaving()
            }
            return
        }

        switch currentPowerSource {
        case .battery:
            enterBatterySaving()
        case .ac:
            restoreFromBatterySaving()
        case .unknown:
            // Default to normal behavior on unknown power source
            break
        }
    }

    /// Enters battery-saving mode based on the configured aggressiveness.
    private func enterBatterySaving() {
        guard !isBatterySaving else { return }
        isBatterySaving = true

        let mode = AuroraSettings.shared.batteryMode
        AuroraLogger.logPerformanceAction("Entering battery-saving mode: \(mode.rawValue)")

        switch mode {
        case .aggressive:
            // Completely pause all wallpapers
            WallpaperManager.shared.pauseAll()

        case .balanced:
            // Reduce playback rate to 0.5x
            WallpaperManager.shared.throttleAll(rate: 0.5)

        case .permissive:
            // Do nothing — user chose to keep playing
            AuroraLogger.logPerformanceAction("Permissive battery mode — no changes")
        }
    }

    /// Restores normal behavior when returning to AC power.
    private func restoreFromBatterySaving() {
        guard isBatterySaving else { return }
        isBatterySaving = false

        AuroraLogger.logPerformanceAction("Restoring from battery-saving mode")

        let wallpaperManager = WallpaperManager.shared

        if wallpaperManager.isPaused {
            wallpaperManager.resumeAll()
        }

        if wallpaperManager.isThrottled {
            wallpaperManager.unthrottleAll()
        }
    }

    // MARK: - Screen Lock Handling

    private func setupScreenLockObservers() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(screenLocked), name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked), name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        AuroraLogger.system.info("Screen lock observers registered")
    }

    @objc private func screenLocked() {
        guard !isScreenLocked else { return }
        isScreenLocked = true
        AuroraLogger.system.info("Screen locked — keeping wallpapers active for lock screen display")
        
        // Force resume playback for lock screen viewing regardless of background app behavior,
        // unless constrained by battery.
        if !isBatterySaving || AuroraSettings.shared.batteryMode != .aggressive {
             if WallpaperManager.shared.isPaused {
                 WallpaperManager.shared.resumeAll()
             }
        }
    }

    @objc private func screenUnlocked() {
        guard isScreenLocked else { return }
        isScreenLocked = false
        AuroraLogger.system.info("Screen unlocked — restoring normal state")
        
        // Re-evaluate performance state to either resume normally or pause if a 
        // fullscreen app/focused app justifies it.
        if !isBatterySaving || AuroraSettings.shared.batteryMode != .aggressive {
            // Re-evaluate what should be playing. forceReevaluation will trigger resume if allowed
            PerformanceMonitor.shared.forceReevaluation()
        }
    }

    // MARK: - Cleanup

    func stopMonitoring() {
        powerCheckTimer?.invalidate()
        powerCheckTimer = nil
        DistributedNotificationCenter.default().removeObserver(self)
        AuroraLogger.system.info("Power monitoring stopped")
    }
}
