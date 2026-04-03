// Aurora — StatusBarController
// Menu bar (NSStatusItem) app with quick controls: play/pause, change wallpaper,
// preferences, and quit.

import AppKit

/// Manages the menu bar status item and its dropdown menu.
final class StatusBarController {

    // MARK: - Properties

    /// The status bar item.
    private var statusItem: NSStatusItem?

    /// The dropdown menu.
    private var menu: NSMenu?

    /// Play/Pause menu item (needs dynamic title).
    private var playPauseItem: NSMenuItem?

    /// Current wallpaper name display.
    private var currentWallpaperItem: NSMenuItem?

    /// Preferences window controller.
    private var preferencesWindow: PreferencesWindow?

    // MARK: - Init

    init() {
        setupStatusItem()
        AuroraLogger.ui.info("StatusBarController initialized")
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Use SF Symbol for the menu bar icon
            if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Aurora") {
                image.isTemplate = true  // Adapts to light/dark menu bar
                button.image = image
            } else {
                button.title = "✦"
            }
            button.toolTip = "Aurora Live Wallpaper"
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Current wallpaper indicator
        currentWallpaperItem = NSMenuItem(title: "No wallpaper set", action: nil, keyEquivalent: "")
        currentWallpaperItem?.isEnabled = false
        if let item = currentWallpaperItem {
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Play / Pause
        playPauseItem = NSMenuItem(
            title: "Pause Wallpaper",
            action: #selector(togglePlayback),
            keyEquivalent: "p"
        )
        playPauseItem?.target = self
        if let item = playPauseItem {
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // Change Wallpaper → opens library
        let changeItem = NSMenuItem(
            title: "Change Wallpaper...",
            action: #selector(showLibrary),
            keyEquivalent: "w"
        )
        changeItem.target = self
        menu.addItem(changeItem)

        // Import Wallpaper → file picker
        let importItem = NSMenuItem(
            title: "Import Wallpaper...",
            action: #selector(importWallpaper),
            keyEquivalent: "i"
        )
        importItem.target = self
        menu.addItem(importItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferencesAction),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Aurora",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func togglePlayback() {
        WallpaperManager.shared.toggleAll()
        updatePlayPauseTitle()
    }

    @objc private func showLibrary() {
        let prefsWindow = getPreferencesWindow()
        prefsWindow.showWindow(nil)
        prefsWindow.selectLibraryTab()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func importWallpaper() {
        ImportHandler.shared.importFromFilePicker { [weak self] wallpaper in
            if let wallpaper = wallpaper {
                // Apply to main display
                WallpaperManager.shared.setWallpaper(wallpaper)
                self?.updateCurrentWallpaperDisplay(name: wallpaper.name)
            }
        }
    }

    @objc private func showPreferencesAction() {
        showPreferences()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Public

    /// Shows the preferences window.
    func showPreferences() {
        let prefsWindow = getPreferencesWindow()
        prefsWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - State Updates

    /// Updates the play/pause menu item title based on current state.
    func updatePlayPauseTitle() {
        let isPaused = WallpaperManager.shared.isPaused
        playPauseItem?.title = isPaused ? "Resume Wallpaper" : "Pause Wallpaper"
    }

    /// Updates the current wallpaper name display.
    func updateCurrentWallpaperDisplay(name: String) {
        currentWallpaperItem?.title = "♦ \(name)"
    }

    // MARK: - Helpers

    private func getPreferencesWindow() -> PreferencesWindow {
        if let existing = preferencesWindow {
            return existing
        }
        let prefs = PreferencesWindow()
        preferencesWindow = prefs
        return prefs
    }
}
