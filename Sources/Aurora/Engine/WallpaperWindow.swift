// Aurora — WallpaperWindow
// Borderless NSWindow positioned at the desktop level, behind Finder icons.
// Includes fade-in animation to prevent visual flicker on creation/recreation.

import AppKit
import QuartzCore

/// A borderless, click-through window that sits behind Finder's desktop icons.
///
/// Window stack (top to bottom):
///   Normal windows → Finder desktop icons → ★ WallpaperWindow ★ → macOS desktop bg
///
final class WallpaperWindow: NSWindow {

    // MARK: - Properties

    /// The display this window is attached to.
    let targetScreen: NSScreen

    /// Unique display identifier for this window's screen.
    let displayID: CGDirectDisplayID

    // MARK: - Init

    /// Creates a wallpaper window for the given screen.
    /// - Parameter screen: The NSScreen to cover with this wallpaper window.
    init(for screen: NSScreen) {
        self.targetScreen = screen
        self.displayID = screen.displayID

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        configureWindow()
        AuroraLogger.logWindowState("Created wallpaper window for display \(displayID) at \(screen.frame)")
    }

    // MARK: - Configuration

    private func configureWindow() {
        // Place window just below Finder's desktop icon layer
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)

        // Behavior: appear on all Spaces, don't move in Mission Control, hidden from Cmd+Tab
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Click-through: all mouse events pass to desktop/Finder
        ignoresMouseEvents = true

        // No shadow, no opacity initially (for fade-in)
        hasShadow = false
        alphaValue = 0.0

        // Make the window background transparent
        backgroundColor = .clear
        isOpaque = false

        // Prevent the window from being released when closed
        isReleasedWhenClosed = false
        
        // Show on lock screen
        canBecomeVisibleWithoutLogin = true

        // Window cannot become key or main — it's just a display surface
        // (handled by override below)
    }

    // MARK: - Key/Main Prevention

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Display

    /// Shows the window with a fade-in animation to prevent flicker.
    /// - Parameter duration: Fade-in duration in seconds. Default: 0.3s.
    func showWithFadeIn(duration: TimeInterval = 0.3) {
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 1.0
        }

        AuroraLogger.logWindowState("Showing wallpaper window for display \(displayID) with fade-in")
    }

    /// Hides the window with a fade-out animation.
    /// - Parameter duration: Fade-out duration in seconds. Default: 0.2s.
    func hideWithFadeOut(duration: TimeInterval = 0.2, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            completion?()
        })

        AuroraLogger.logWindowState("Hiding wallpaper window for display \(displayID) with fade-out")
    }

    /// Updates the window frame to match the screen's current frame.
    /// Called when screen resolution or position changes.
    func updateFrame() {
        setFrame(targetScreen.frame, display: true)
        AuroraLogger.logWindowState("Updated frame for display \(displayID) to \(targetScreen.frame)")
    }

    // MARK: - Validation

    /// Checks if this window is still correctly positioned in the window stack.
    /// Returns false if the window has been detached or moved out of the correct level.
    var isHealthy: Bool {
        let correctLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        let isVisible = isVisible && alphaValue > 0
        let isCorrectLevel = level == correctLevel
        let isCorrectFrame = frame == targetScreen.frame

        if !isVisible || !isCorrectLevel || !isCorrectFrame {
            AuroraLogger.logFailure(
                "Health check failed for display \(displayID): " +
                "visible=\(isVisible), correctLevel=\(isCorrectLevel), correctFrame=\(isCorrectFrame)"
            )
            return false
        }
        return true
    }

    // MARK: - Cleanup

    /// Properly cleans up the window before deallocation.
    func cleanup() {
        AuroraLogger.logWindowState("Cleaning up wallpaper window for display \(displayID)")
        contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        orderOut(nil)
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    /// Returns the CGDirectDisplayID for this screen.
    var displayID: CGDirectDisplayID {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return screenNumber.uint32Value
    }
}
