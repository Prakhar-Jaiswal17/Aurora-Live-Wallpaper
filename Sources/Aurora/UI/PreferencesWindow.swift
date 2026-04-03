// Aurora — PreferencesWindow
// Tabbed NSWindowController with General, Performance, and Library tabs.
// Uses NSVisualEffectView for native macOS vibrancy.

import AppKit

/// Main preferences/settings window.
final class PreferencesWindow: NSWindowController {

    // MARK: - Properties

    private var tabView: NSTabView!
    private var libraryViewController: LibraryViewController?

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Aurora Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        // Vibrancy effect
        let visualEffectView = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.material = .sidebar
        visualEffectView.state = .active
        window.contentView?.addSubview(visualEffectView, positioned: .below, relativeTo: nil)

        self.init(window: window)
        setupTabs()
    }

    // MARK: - Tab Setup

    private func setupTabs() {
        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: 680, height: 660))
        tabView.autoresizingMask = [.width, .height]

        // General Tab
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view = createGeneralTab()
        tabView.addTabViewItem(generalTab)

        // Performance Tab
        let performanceTab = NSTabViewItem(identifier: "performance")
        performanceTab.label = "Performance"
        performanceTab.view = createPerformanceTab()
        tabView.addTabViewItem(performanceTab)

        // Library Tab
        let libraryTab = NSTabViewItem(identifier: "library")
        libraryTab.label = "Library"
        let libVC = LibraryViewController()
        libraryViewController = libVC
        let libraryContainerView = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 620))
        libVC.view.frame = libraryContainerView.bounds
        libVC.view.translatesAutoresizingMaskIntoConstraints = false
        libraryContainerView.addSubview(libVC.view)
        NSLayoutConstraint.activate([
            libVC.view.topAnchor.constraint(equalTo: libraryContainerView.topAnchor),
            libVC.view.bottomAnchor.constraint(equalTo: libraryContainerView.bottomAnchor),
            libVC.view.leadingAnchor.constraint(equalTo: libraryContainerView.leadingAnchor),
            libVC.view.trailingAnchor.constraint(equalTo: libraryContainerView.trailingAnchor),
        ])
        libraryTab.view = libraryContainerView
        tabView.addTabViewItem(libraryTab)

        window?.contentView?.addSubview(tabView)
    }

    /// Switches to the Library tab.
    func selectLibraryTab() {
        tabView?.selectTabViewItem(at: 2)
    }

    // MARK: - General Tab

    private func createGeneralTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 620))
        let settings = AuroraSettings.shared

        var yOffset: CGFloat = 560

        // Title
        let titleLabel = createLabel("General Settings", bold: true, size: 16)
        titleLabel.frame = NSRect(x: 30, y: yOffset, width: 300, height: 24)
        view.addSubview(titleLabel)
        yOffset -= 50

        // Launch at Login
        let launchCheckbox = NSButton(checkboxWithTitle: "Launch Aurora at login", target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchCheckbox.state = settings.launchAtLogin ? .on : .off
        launchCheckbox.frame = NSRect(x: 30, y: yOffset, width: 300, height: 24)
        view.addSubview(launchCheckbox)
        yOffset -= 35

        // Restore Last Session
        let restoreCheckbox = NSButton(checkboxWithTitle: "Restore wallpapers from last session on launch", target: self, action: #selector(toggleRestoreSession(_:)))
        restoreCheckbox.state = settings.restoreLastSession ? .on : .off
        restoreCheckbox.frame = NSRect(x: 30, y: yOffset, width: 400, height: 24)
        view.addSubview(restoreCheckbox)
        yOffset -= 50

        // Default Playback Settings section
        let playbackLabel = createLabel("Default Playback Settings", bold: true, size: 14)
        playbackLabel.frame = NSRect(x: 30, y: yOffset, width: 300, height: 20)
        view.addSubview(playbackLabel)
        yOffset -= 35

        // Loop by default
        let loopCheckbox = NSButton(checkboxWithTitle: "Loop wallpapers by default", target: self, action: #selector(toggleDefaultLoop(_:)))
        loopCheckbox.state = settings.defaultPlaybackSettings.isLooping ? .on : .off
        loopCheckbox.frame = NSRect(x: 30, y: yOffset, width: 300, height: 24)
        view.addSubview(loopCheckbox)
        yOffset -= 35

        // Mute by default
        let muteCheckbox = NSButton(checkboxWithTitle: "Mute audio by default", target: self, action: #selector(toggleDefaultMute(_:)))
        muteCheckbox.state = settings.defaultPlaybackSettings.isMuted ? .on : .off
        muteCheckbox.frame = NSRect(x: 30, y: yOffset, width: 300, height: 24)
        view.addSubview(muteCheckbox)
        yOffset -= 50

        // ── Wallpaper Cycling Section ──
        let cycleLabel = createLabel("Wallpaper Cycling", bold: true, size: 14)
        cycleLabel.frame = NSRect(x: 30, y: yOffset, width: 300, height: 20)
        view.addSubview(cycleLabel)
        yOffset -= 10

        let cycleDesc = createLabel("Automatically cycle through library wallpapers at a set interval", bold: false, size: 12)
        cycleDesc.textColor = .secondaryLabelColor
        cycleDesc.frame = NSRect(x: 30, y: yOffset, width: 500, height: 16)
        view.addSubview(cycleDesc)
        yOffset -= 35

        // Enable checkbox
        let cycleCheckbox = NSButton(checkboxWithTitle: "Enable wallpaper cycling", target: self, action: #selector(toggleCycleEnabled(_:)))
        cycleCheckbox.state = settings.cycleEnabled ? .on : .off
        cycleCheckbox.frame = NSRect(x: 30, y: yOffset, width: 300, height: 24)
        view.addSubview(cycleCheckbox)
        yOffset -= 35

        // Interval row: "Every [__] [Minutes ▾]"
        let everyLabel = createLabel("Every", bold: false, size: 13)
        everyLabel.frame = NSRect(x: 48, y: yOffset, width: 40, height: 22)
        view.addSubview(everyLabel)

        let intervalField = NSTextField(frame: NSRect(x: 95, y: yOffset, width: 80, height: 24))
        intervalField.doubleValue = settings.cycleInterval
        intervalField.formatter = cycleIntervalFormatter()
        intervalField.alignment = .center
        intervalField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        intervalField.target = self
        intervalField.action = #selector(cycleIntervalChanged(_:))
        intervalField.tag = 500
        intervalField.isEnabled = settings.cycleEnabled
        view.addSubview(intervalField)

        let unitPopup = NSPopUpButton(frame: NSRect(x: 185, y: yOffset - 1, width: 110, height: 26))
        for unit in CycleUnit.allCases {
            unitPopup.addItem(withTitle: unit.displayName)
        }
        unitPopup.selectItem(withTitle: settings.cycleUnit.displayName)
        unitPopup.target = self
        unitPopup.action = #selector(cycleUnitChanged(_:))
        unitPopup.tag = 501
        unitPopup.isEnabled = settings.cycleEnabled
        view.addSubview(unitPopup)

        // Preview label showing the computed time
        let previewText = formatCyclePreview(interval: settings.cycleInterval, unit: settings.cycleUnit)
        let cyclePreviewLabel = createLabel(previewText, bold: false, size: 11)
        cyclePreviewLabel.textColor = .tertiaryLabelColor
        cyclePreviewLabel.frame = NSRect(x: 310, y: yOffset + 2, width: 250, height: 18)
        cyclePreviewLabel.tag = 502
        view.addSubview(cyclePreviewLabel)

        return view
    }

    // MARK: - Performance Tab

    private func createPerformanceTab() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 620))
        let settings = AuroraSettings.shared

        var yOffset: CGFloat = 560

        // Title
        let titleLabel = createLabel("Performance Settings", bold: true, size: 16)
        titleLabel.frame = NSRect(x: 30, y: yOffset, width: 300, height: 24)
        view.addSubview(titleLabel)
        yOffset -= 40

        // Fullscreen pause
        let fullscreenCheckbox = NSButton(checkboxWithTitle: "Pause wallpaper when a fullscreen app is active", target: self, action: #selector(toggleFullscreenPause(_:)))
        fullscreenCheckbox.state = settings.pauseOnFullscreen ? .on : .off
        fullscreenCheckbox.frame = NSRect(x: 30, y: yOffset, width: 400, height: 24)
        view.addSubview(fullscreenCheckbox)
        yOffset -= 35

        // Background App Focus
        let bgLabel = createLabel("When Another Window is Active", bold: true, size: 14)
        bgLabel.frame = NSRect(x: 30, y: yOffset, width: 300, height: 20)
        view.addSubview(bgLabel)
        yOffset -= 10

        let bgDesc = createLabel("Controls what happens when you are working in another window", bold: false, size: 12)
        bgDesc.textColor = .secondaryLabelColor
        bgDesc.frame = NSRect(x: 30, y: yOffset, width: 500, height: 16)
        view.addSubview(bgDesc)
        yOffset -= 25

        let bgModes: [(BackgroundBehavior, String)] = [
            (.keepPlaying, "Keep playing normally"),
            (.lowerFramerate, "Lower framerate (refresh rate)"),
            (.pause, "Pause wallpaper")
        ]

        var throttleRadioBtn: NSButton?

        for (mode, title) in bgModes {
            let radio = NSButton(radioButtonWithTitle: title, target: self, action: #selector(backgroundModeChanged(_:)))
            radio.tag = bgModes.firstIndex(where: { $0.0 == mode })! + 200
            radio.state = settings.backgroundBehavior == mode ? .on : .off
            radio.frame = NSRect(x: 48, y: yOffset, width: 300, height: 22)
            view.addSubview(radio)
            
            if mode == .lowerFramerate {
                throttleRadioBtn = radio
            }
            yOffset -= 28
        }
        
        yOffset += 28 // Go back line to add slider
        
        // Framerate slider (enabled only if lowerFramerate is selected)
        let fpsSlider = NSSlider(value: Double(settings.backgroundFramerate), minValue: 1, maxValue: 60, target: self, action: #selector(backgroundFramerateChanged(_:)))
        fpsSlider.frame = NSRect(x: 320, y: yOffset + 2, width: 150, height: 20)
        fpsSlider.tag = 300
        fpsSlider.isEnabled = settings.backgroundBehavior == .lowerFramerate
        view.addSubview(fpsSlider)

        let fpsLabel = createLabel("\(settings.backgroundFramerate) FPS", bold: true, size: 12)
        fpsLabel.frame = NSRect(x: 480, y: yOffset + 2, width: 60, height: 18)
        fpsLabel.tag = 301
        fpsLabel.textColor = settings.backgroundBehavior == .lowerFramerate ? .labelColor : .disabledControlTextColor
        view.addSubview(fpsLabel)

        yOffset -= 40

        // Battery section
        let batteryLabel = createLabel("Battery Mode", bold: true, size: 14)
        batteryLabel.frame = NSRect(x: 30, y: yOffset, width: 300, height: 20)
        view.addSubview(batteryLabel)
        yOffset -= 10

        let batteryDesc = createLabel("Controls wallpaper behavior when running on battery power", bold: false, size: 12)
        batteryDesc.textColor = .secondaryLabelColor
        batteryDesc.frame = NSRect(x: 30, y: yOffset, width: 500, height: 16)
        view.addSubview(batteryDesc)
        yOffset -= 35

        // Battery mode radio buttons
        let modes: [(BatteryMode, String)] = [
            (.aggressive, "Pause wallpaper (saves most battery)"),
            (.balanced, "Reduce speed to 0.5x (balanced)"),
            (.permissive, "Keep playing normally (uses more battery)")
        ]

        for (mode, title) in modes {
            let radio = NSButton(radioButtonWithTitle: title, target: self, action: #selector(batteryModeChanged(_:)))
            radio.tag = modes.firstIndex(where: { $0.0 == mode })!
            radio.state = settings.batteryMode == mode ? .on : .off
            radio.frame = NSRect(x: 48, y: yOffset, width: 450, height: 22)
            view.addSubview(radio)
            yOffset -= 28
        }

        yOffset -= 20

        // CPU threshold slider
        let cpuLabel = createLabel("CPU Usage Threshold: \(Int(settings.cpuThreshold))%", bold: true, size: 14)
        cpuLabel.frame = NSRect(x: 30, y: yOffset, width: 300, height: 20)
        cpuLabel.tag = 100  // Tag for updating
        view.addSubview(cpuLabel)
        yOffset -= 10

        let cpuDesc = createLabel("Throttle wallpaper when system CPU usage exceeds this value", bold: false, size: 12)
        cpuDesc.textColor = .secondaryLabelColor
        cpuDesc.frame = NSRect(x: 30, y: yOffset, width: 500, height: 16)
        view.addSubview(cpuDesc)
        yOffset -= 30

        let slider = NSSlider(value: settings.cpuThreshold, minValue: 50, maxValue: 100, target: self, action: #selector(cpuThresholdChanged(_:)))
        slider.frame = NSRect(x: 30, y: yOffset, width: 300, height: 24)
        slider.isContinuous = true
        view.addSubview(slider)

        return view
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        AuroraSettings.shared.launchAtLogin = sender.state == .on
    }

    @objc private func toggleRestoreSession(_ sender: NSButton) {
        AuroraSettings.shared.restoreLastSession = sender.state == .on
    }

    @objc private func toggleDefaultLoop(_ sender: NSButton) {
        var settings = AuroraSettings.shared.defaultPlaybackSettings
        settings.isLooping = sender.state == .on
        AuroraSettings.shared.defaultPlaybackSettings = settings
    }

    @objc private func toggleDefaultMute(_ sender: NSButton) {
        var settings = AuroraSettings.shared.defaultPlaybackSettings
        settings.isMuted = sender.state == .on
        AuroraSettings.shared.defaultPlaybackSettings = settings
    }

    @objc private func toggleFullscreenPause(_ sender: NSButton) {
        AuroraSettings.shared.pauseOnFullscreen = sender.state == .on
    }

    @objc private func backgroundModeChanged(_ sender: NSButton) {
        let modes: [BackgroundBehavior] = [.keepPlaying, .lowerFramerate, .pause]
        let index = sender.tag - 200
        if index >= 0 && index < modes.count {
            AuroraSettings.shared.backgroundBehavior = modes[index]
            AuroraLogger.ui.info("Background behavior changed to: \(modes[index].rawValue)")
            
            // Enable/disable FPS slider
            if let slider = sender.superview?.viewWithTag(300) as? NSSlider,
               let label = sender.superview?.viewWithTag(301) as? NSTextField {
                let isLower = modes[index] == .lowerFramerate
                slider.isEnabled = isLower
                label.textColor = isLower ? .labelColor : .disabledControlTextColor
            }
        }
    }

    @objc private func backgroundFramerateChanged(_ sender: NSSlider) {
        let fps = sender.integerValue
        AuroraSettings.shared.backgroundFramerate = fps
        if let label = sender.superview?.viewWithTag(301) as? NSTextField {
            label.stringValue = "\(fps) FPS"
        }
    }

    @objc private func batteryModeChanged(_ sender: NSButton) {
        let modes: [BatteryMode] = [.aggressive, .balanced, .permissive]
        if sender.tag < modes.count {
            AuroraSettings.shared.batteryMode = modes[sender.tag]
            AuroraLogger.ui.info("Battery mode changed to: \(modes[sender.tag].rawValue, privacy: .public)")
        }
    }

    @objc private func cpuThresholdChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        AuroraSettings.shared.cpuThreshold = value

        // Update the label
        if let label = sender.superview?.viewWithTag(100) as? NSTextField {
            label.stringValue = "CPU Usage Threshold: \(Int(value))%"
        }
    }

    // MARK: - Helpers

    private func createLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }

    // MARK: - Cycle Actions

    @objc private func toggleCycleEnabled(_ sender: NSButton) {
        let enabled = sender.state == .on
        AuroraSettings.shared.cycleEnabled = enabled

        // Enable/disable the interval field and unit popup
        if let intervalField = sender.superview?.viewWithTag(500) as? NSTextField {
            intervalField.isEnabled = enabled
        }
        if let unitPopup = sender.superview?.viewWithTag(501) as? NSPopUpButton {
            unitPopup.isEnabled = enabled
        }
        AuroraLogger.ui.info("Wallpaper cycling \(enabled ? "enabled" : "disabled")")
    }

    @objc private func cycleIntervalChanged(_ sender: NSTextField) {
        let value = sender.doubleValue
        guard value > 0 else { return }
        AuroraSettings.shared.cycleInterval = value
        updateCyclePreviewLabel(in: sender.superview)
    }

    @objc private func cycleUnitChanged(_ sender: NSPopUpButton) {
        let units = CycleUnit.allCases
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < units.count else { return }
        AuroraSettings.shared.cycleUnit = units[index]
        updateCyclePreviewLabel(in: sender.superview)
    }

    private func updateCyclePreviewLabel(in parentView: NSView?) {
        guard let label = parentView?.viewWithTag(502) as? NSTextField else { return }
        let settings = AuroraSettings.shared
        label.stringValue = formatCyclePreview(interval: settings.cycleInterval, unit: settings.cycleUnit)
    }

    private func formatCyclePreview(interval: Double, unit: CycleUnit) -> String {
        let totalSeconds = AuroraSettings.shared.cycleIntervalSeconds
        if totalSeconds < 60 {
            return "= \(Int(totalSeconds))s between changes"
        } else if totalSeconds < 3600 {
            return String(format: "= %.1f min between changes", totalSeconds / 60.0)
        } else if totalSeconds < 86400 {
            return String(format: "= %.1f hr between changes", totalSeconds / 3600.0)
        } else {
            return String(format: "= %.1f days between changes", totalSeconds / 86400.0)
        }
    }

    /// Creates a number formatter that allows decimal input for the cycle interval.
    private func cycleIntervalFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0.1
        formatter.maximum = 9999
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.allowsFloats = true
        return formatter
    }
}
