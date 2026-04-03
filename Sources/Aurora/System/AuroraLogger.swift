// Aurora — AuroraLogger
// Structured logging via OSLog with categorized subsystems.

import Foundation
import os.log

/// Centralized logging for Aurora using OSLog.
/// Categories: engine, system, ui, performance.
final class AuroraLogger {

    // MARK: - Subsystem

    private static let subsystem = "com.aurora.livewallpaper"

    // MARK: - Category Loggers

    /// Logs related to the wallpaper engine (window creation, playback, cleanup).
    static let engine = Logger(subsystem: subsystem, category: "engine")

    /// Logs related to system integration (displays, power, spaces).
    static let system = Logger(subsystem: subsystem, category: "system")

    /// Logs related to the user interface (menu bar, preferences, library).
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Logs related to performance monitoring (fullscreen, CPU, throttling).
    static let performance = Logger(subsystem: subsystem, category: "performance")

    // MARK: - Convenience

    /// Log a recovery event (engine recovered from a failure).
    static func logRecovery(_ message: String) {
        engine.info("🔄 RECOVERY: \(message, privacy: .public)")
    }

    /// Log a failure event that requires attention.
    static func logFailure(_ message: String) {
        engine.error("❌ FAILURE: \(message, privacy: .public)")
    }

    /// Log a window-state change (created, destroyed, repositioned).
    static func logWindowState(_ message: String) {
        engine.info("🪟 WINDOW: \(message, privacy: .public)")
    }

    /// Log a performance decision (pause, throttle, resume).
    static func logPerformanceAction(_ message: String) {
        performance.info("⚡ PERF: \(message, privacy: .public)")
    }
}
