// Aurora — PreferencesWindow
// Tabbed NSWindowController with General, Performance, and Library tabs.
// Uses NSVisualEffectView for native macOS vibrancy.
// All tabs use Auto Layout with NSStackView for consistent, polished spacing.

import AppKit

/// Main preferences/settings window.
final class PreferencesWindow: NSWindowController {

    // MARK: - Properties

    private var tabView: NSTabView!
    private var libraryViewController: LibraryViewController?

    // MARK: - Layout Constants

    private enum Layout {
        static let windowWidth: CGFloat = 680
        static let windowHeight: CGFloat = 660

        static let sectionSpacing: CGFloat = 28       // Between major sections
        static let controlSpacing: CGFloat = 10       // Between controls within a section
        static let subtitleGap: CGFloat = 2           // Between title and subtitle
        static let contentInsetTop: CGFloat = 28
        static let contentInsetBottom: CGFloat = 28
        static let contentInsetLeading: CGFloat = 32
        static let contentInsetTrailing: CGFloat = 32
        static let indentLeading: CGFloat = 18        // Sub-controls indent
    }

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Aurora Preferences"
        window.center()
        window.minSize = NSSize(width: Layout.windowWidth, height: Layout.windowHeight)
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
        tabView = NSTabView(frame: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: Layout.windowHeight))
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
        let libraryContainerView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: 620))
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
        let settings = AuroraSettings.shared

        // Root stack view for the entire tab
        let rootStack = createRootStack()

        // ── General Settings ──
        let generalTitle = createSectionTitle("General Settings")
        rootStack.addArrangedSubview(generalTitle)
        rootStack.setCustomSpacing(Layout.controlSpacing + 4, after: generalTitle)

        // Launch at Login
        let launchCheckbox = NSButton(checkboxWithTitle: "Launch Aurora at login", target: self, action: #selector(toggleLaunchAtLogin(_:)))
        launchCheckbox.state = settings.launchAtLogin ? .on : .off
        launchCheckbox.font = .systemFont(ofSize: 13)
        rootStack.addArrangedSubview(launchCheckbox)
        rootStack.setCustomSpacing(Layout.controlSpacing, after: launchCheckbox)

        // Restore Last Session
        let restoreCheckbox = NSButton(checkboxWithTitle: "Restore wallpapers from last session on launch", target: self, action: #selector(toggleRestoreSession(_:)))
        restoreCheckbox.state = settings.restoreLastSession ? .on : .off
        restoreCheckbox.font = .systemFont(ofSize: 13)
        rootStack.addArrangedSubview(restoreCheckbox)

        // ── Separator ──
        rootStack.addArrangedSubview(createSeparator())

        // ── Default Playback Settings ──
        let playbackTitle = createSectionTitle("Default Playback Settings")
        rootStack.addArrangedSubview(playbackTitle)
        rootStack.setCustomSpacing(Layout.controlSpacing + 4, after: playbackTitle)

        // Loop by default
        let loopCheckbox = NSButton(checkboxWithTitle: "Loop wallpapers by default", target: self, action: #selector(toggleDefaultLoop(_:)))
        loopCheckbox.state = settings.defaultPlaybackSettings.isLooping ? .on : .off
        loopCheckbox.font = .systemFont(ofSize: 13)
        rootStack.addArrangedSubview(loopCheckbox)
        rootStack.setCustomSpacing(Layout.controlSpacing, after: loopCheckbox)

        // Mute by default
        let muteCheckbox = NSButton(checkboxWithTitle: "Mute audio by default", target: self, action: #selector(toggleDefaultMute(_:)))
        muteCheckbox.state = settings.defaultPlaybackSettings.isMuted ? .on : .off
        muteCheckbox.font = .systemFont(ofSize: 13)
        rootStack.addArrangedSubview(muteCheckbox)

        // ── Separator ──
        rootStack.addArrangedSubview(createSeparator())

        // ── Wallpaper Cycling ──
        let cycleTitle = createSectionTitle("Wallpaper Cycling")
        rootStack.addArrangedSubview(cycleTitle)
        rootStack.setCustomSpacing(Layout.subtitleGap, after: cycleTitle)

        let cycleDesc = createSubtitle("Automatically cycle through library wallpapers at a set interval")
        rootStack.addArrangedSubview(cycleDesc)
        rootStack.setCustomSpacing(Layout.controlSpacing + 4, after: cycleDesc)

        // Enable checkbox
        let cycleCheckbox = NSButton(checkboxWithTitle: "Enable wallpaper cycling", target: self, action: #selector(toggleCycleEnabled(_:)))
        cycleCheckbox.state = settings.cycleEnabled ? .on : .off
        cycleCheckbox.font = .systemFont(ofSize: 13)
        rootStack.addArrangedSubview(cycleCheckbox)
        rootStack.setCustomSpacing(Layout.controlSpacing + 2, after: cycleCheckbox)

        // Interval row: "Every [__] [Minutes ▾]  = Xm between changes"
        let intervalRow = NSStackView()
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .centerY
        intervalRow.spacing = 8
        intervalRow.translatesAutoresizingMaskIntoConstraints = false

        // Indent spacer
        let indentSpacer = NSView()
        indentSpacer.translatesAutoresizingMaskIntoConstraints = false
        indentSpacer.widthAnchor.constraint(equalToConstant: Layout.indentLeading).isActive = true
        intervalRow.addArrangedSubview(indentSpacer)

        let everyLabel = createLabel("Every", bold: false, size: 13)
        intervalRow.addArrangedSubview(everyLabel)

        let intervalField = NSTextField()
        intervalField.translatesAutoresizingMaskIntoConstraints = false
        intervalField.doubleValue = settings.cycleInterval
        intervalField.formatter = cycleIntervalFormatter()
        intervalField.alignment = .center
        intervalField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        intervalField.target = self
        intervalField.action = #selector(cycleIntervalChanged(_:))
        intervalField.tag = 500
        intervalField.isEnabled = settings.cycleEnabled
        intervalField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        intervalRow.addArrangedSubview(intervalField)

        let unitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        unitPopup.translatesAutoresizingMaskIntoConstraints = false
        for unit in CycleUnit.allCases {
            unitPopup.addItem(withTitle: unit.displayName)
        }
        unitPopup.selectItem(withTitle: settings.cycleUnit.displayName)
        unitPopup.target = self
        unitPopup.action = #selector(cycleUnitChanged(_:))
        unitPopup.tag = 501
        unitPopup.isEnabled = settings.cycleEnabled
        unitPopup.widthAnchor.constraint(equalToConstant: 100).isActive = true
        intervalRow.addArrangedSubview(unitPopup)

        // Preview label
        let previewText = formatCyclePreview(interval: settings.cycleInterval, unit: settings.cycleUnit)
        let cyclePreviewLabel = createLabel(previewText, bold: false, size: 11)
        cyclePreviewLabel.textColor = .tertiaryLabelColor
        cyclePreviewLabel.tag = 502
        cyclePreviewLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        intervalRow.addArrangedSubview(cyclePreviewLabel)

        rootStack.addArrangedSubview(intervalRow)

        // Wrap in scroll view
        return wrapInScrollView(rootStack)
    }

    // MARK: - Performance Tab

    private func createPerformanceTab() -> NSView {
        let settings = AuroraSettings.shared

        // Root stack view
        let rootStack = createRootStack()

        // ── Performance Settings ──
        let titleLabel = createSectionTitle("Performance Settings")
        rootStack.addArrangedSubview(titleLabel)
        rootStack.setCustomSpacing(Layout.controlSpacing + 4, after: titleLabel)

        // Fullscreen pause
        let fullscreenCheckbox = NSButton(checkboxWithTitle: "Pause wallpaper when a fullscreen app is active", target: self, action: #selector(toggleFullscreenPause(_:)))
        fullscreenCheckbox.state = settings.pauseOnFullscreen ? .on : .off
        fullscreenCheckbox.font = .systemFont(ofSize: 13)
        rootStack.addArrangedSubview(fullscreenCheckbox)

        // ── Separator ──
        rootStack.addArrangedSubview(createSeparator())

        // ── When Another Window is Active ──
        let bgTitle = createSectionTitle("When Another Window is Active")
        rootStack.addArrangedSubview(bgTitle)
        rootStack.setCustomSpacing(Layout.subtitleGap, after: bgTitle)

        let bgDesc = createSubtitle("Controls what happens when you are working in another window")
        rootStack.addArrangedSubview(bgDesc)
        rootStack.setCustomSpacing(Layout.controlSpacing + 4, after: bgDesc)

        // Background mode radio buttons
        let bgModes: [(BackgroundBehavior, String)] = [
            (.keepPlaying, "Keep playing normally"),
            (.lowerFramerate, "Lower framerate (refresh rate)"),
            (.pause, "Pause wallpaper")
        ]

        for (index, (mode, title)) in bgModes.enumerated() {
            if mode == .lowerFramerate {
                // Lower framerate radio with inline FPS slider
                let fpsRow = createRadioWithSliderRow(
                    radioTitle: title,
                    radioTag: index + 200,
                    isSelected: settings.backgroundBehavior == mode,
                    sliderValue: Double(settings.backgroundFramerate),
                    sliderTag: 300,
                    labelTag: 301,
                    labelText: "\(settings.backgroundFramerate) FPS",
                    sliderEnabled: settings.backgroundBehavior == .lowerFramerate,
                    target: self,
                    radioAction: #selector(backgroundModeChanged(_:)),
                    sliderAction: #selector(backgroundFramerateChanged(_:))
                )
                rootStack.addArrangedSubview(fpsRow)
                rootStack.setCustomSpacing(Layout.controlSpacing - 2, after: fpsRow)
            } else {
                // Keep playing / Pause — plain radio button (no slider)
                let radio = NSButton(radioButtonWithTitle: title, target: self, action: #selector(backgroundModeChanged(_:)))
                radio.tag = index + 200
                radio.state = settings.backgroundBehavior == mode ? .on : .off
                radio.font = .systemFont(ofSize: 13)

                let indentedRadio = createIndentedView(radio)
                rootStack.addArrangedSubview(indentedRadio)
                rootStack.setCustomSpacing(Layout.controlSpacing - 2, after: indentedRadio)
            }
        }

        // ── Separator ──
        rootStack.addArrangedSubview(createSeparator())

        // ── Battery Mode ──
        let batteryTitle = createSectionTitle("Battery Mode")
        rootStack.addArrangedSubview(batteryTitle)
        rootStack.setCustomSpacing(Layout.subtitleGap, after: batteryTitle)

        let batteryDesc = createSubtitle("Controls wallpaper behavior when running on battery power")
        rootStack.addArrangedSubview(batteryDesc)
        rootStack.setCustomSpacing(Layout.controlSpacing + 4, after: batteryDesc)

        let modes: [(BatteryMode, String)] = [
            (.aggressive, "Pause wallpaper (saves most battery)"),
            (.balanced, "Reduce speed to 0.5x (balanced)"),
            (.permissive, "Keep playing normally (uses more battery)")
        ]

        for (index, (mode, title)) in modes.enumerated() {
            let radio = NSButton(radioButtonWithTitle: title, target: self, action: #selector(batteryModeChanged(_:)))
            radio.tag = index + 400
            radio.state = settings.batteryMode == mode ? .on : .off
            radio.font = .systemFont(ofSize: 13)

            let indentedRadio = createIndentedView(radio)
            rootStack.addArrangedSubview(indentedRadio)

            if index < modes.count - 1 {
                rootStack.setCustomSpacing(Layout.controlSpacing - 2, after: indentedRadio)
            }
        }

        // ── Separator ──
        rootStack.addArrangedSubview(createSeparator())

        // ── CPU Usage Threshold ──
        let cpuTitle = createSectionTitle("CPU Usage Threshold: \(Int(settings.cpuThreshold))%")
        cpuTitle.tag = 100
        rootStack.addArrangedSubview(cpuTitle)
        rootStack.setCustomSpacing(Layout.subtitleGap, after: cpuTitle)

        let cpuDesc = createSubtitle("Throttle wallpaper when system CPU usage exceeds this value")
        rootStack.addArrangedSubview(cpuDesc)
        rootStack.setCustomSpacing(Layout.controlSpacing + 4, after: cpuDesc)

        let slider = NSSlider(value: settings.cpuThreshold, minValue: 50, maxValue: 100, target: self, action: #selector(cpuThresholdChanged(_:)))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 320).isActive = true
        rootStack.addArrangedSubview(slider)

        // Wrap in scroll view
        return wrapInScrollView(rootStack)
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

            // Manually deselect sibling radio buttons (they don't auto-group
            // because each lives in a different NSStackView wrapper)
            if let tabContent = sender.window?.contentView {
                for tag in [200, 201, 202] {
                    if tag != sender.tag,
                       let otherRadio = tabContent.findView(withTag: tag) as? NSButton {
                        otherRadio.state = .off
                    }
                }

                // Enable/disable FPS slider
                let isLower = modes[index] == .lowerFramerate
                if let slider = tabContent.findView(withTag: 300) as? NSSlider {
                    slider.isEnabled = isLower
                }
                if let label = tabContent.findView(withTag: 301) as? NSTextField {
                    label.textColor = isLower ? .labelColor : .disabledControlTextColor
                }
            }
        }
    }

    @objc private func backgroundFramerateChanged(_ sender: NSSlider) {
        let fps = sender.integerValue
        AuroraSettings.shared.backgroundFramerate = fps
        if let tabContent = sender.window?.contentView,
           let label = tabContent.findView(withTag: 301) as? NSTextField {
            label.stringValue = "\(fps) FPS"
        }
    }

    @objc private func batteryModeChanged(_ sender: NSButton) {
        let modes: [BatteryMode] = [.aggressive, .balanced, .permissive]
        let index = sender.tag - 400
        if index >= 0 && index < modes.count {
            AuroraSettings.shared.batteryMode = modes[index]
            AuroraLogger.ui.info("Battery mode changed to: \(modes[index].rawValue, privacy: .public)")

            // Manually deselect sibling radio buttons
            if let tabContent = sender.window?.contentView {
                for tag in [400, 401, 402] {
                    if tag != sender.tag,
                       let otherRadio = tabContent.findView(withTag: tag) as? NSButton {
                        otherRadio.state = .off
                    }
                }
            }
        }
    }

    @objc private func cpuThresholdChanged(_ sender: NSSlider) {
        let value = sender.doubleValue
        AuroraSettings.shared.cpuThreshold = value

        // Update the label — search the window hierarchy
        if let tabContent = sender.window?.contentView,
           let label = tabContent.findView(withTag: 100) as? NSTextField {
            label.stringValue = "CPU Usage Threshold: \(Int(value))%"
        }
    }

    // MARK: - Cycle Actions

    @objc private func toggleCycleEnabled(_ sender: NSButton) {
        let enabled = sender.state == .on
        AuroraSettings.shared.cycleEnabled = enabled

        // Enable/disable the interval field and unit popup
        if let tabContent = sender.window?.contentView {
            if let intervalField = tabContent.findView(withTag: 500) as? NSTextField {
                intervalField.isEnabled = enabled
            }
            if let unitPopup = tabContent.findView(withTag: 501) as? NSPopUpButton {
                unitPopup.isEnabled = enabled
            }
        }
        AuroraLogger.ui.info("Wallpaper cycling \(enabled ? "enabled" : "disabled")")
    }

    @objc private func cycleIntervalChanged(_ sender: NSTextField) {
        let value = sender.doubleValue
        guard value > 0 else { return }
        AuroraSettings.shared.cycleInterval = value
        updateCyclePreviewLabel(in: sender.window?.contentView)
    }

    @objc private func cycleUnitChanged(_ sender: NSPopUpButton) {
        let units = CycleUnit.allCases
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < units.count else { return }
        AuroraSettings.shared.cycleUnit = units[index]
        updateCyclePreviewLabel(in: sender.window?.contentView)
    }

    private func updateCyclePreviewLabel(in parentView: NSView?) {
        guard let label = parentView?.findView(withTag: 502) as? NSTextField else { return }
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

    // MARK: - Layout Helpers

    /// Creates the root vertical stack view for a tab with consistent edge insets.
    private func createRootStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Layout.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(
            top: Layout.contentInsetTop,
            left: Layout.contentInsetLeading,
            bottom: Layout.contentInsetBottom,
            right: Layout.contentInsetTrailing
        )
        return stack
    }

    /// Creates a section title label (14pt semibold).
    private func createSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Creates a subtitle/description label (12pt, secondary color).
    private func createSubtitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Creates a basic label.
    private func createLabel(_ text: String, bold: Bool, size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Creates a horizontal separator with vertical spacing.
    private func createSeparator() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(separator)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 1),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 400),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            separator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    /// Wraps a view in an indented container (adds leading padding).
    private func createIndentedView(_ view: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: Layout.indentLeading).isActive = true
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(view)

        return row
    }

    /// Creates a radio button row with an inline slider and label (e.g., for framerate).
    private func createRadioWithSliderRow(
        radioTitle: String,
        radioTag: Int,
        isSelected: Bool,
        sliderValue: Double,
        sliderTag: Int,
        labelTag: Int,
        labelText: String,
        sliderEnabled: Bool,
        target: AnyObject,
        radioAction: Selector,
        sliderAction: Selector
    ) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        // Indent spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: Layout.indentLeading).isActive = true
        row.addArrangedSubview(spacer)

        // Radio button
        let radio = NSButton(radioButtonWithTitle: radioTitle, target: target, action: radioAction)
        radio.tag = radioTag
        radio.state = isSelected ? .on : .off
        radio.font = .systemFont(ofSize: 13)
        radio.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.addArrangedSubview(radio)

        // Slider
        let slider = NSSlider(value: sliderValue, minValue: 1, maxValue: 60, target: target, action: sliderAction)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.tag = sliderTag
        slider.isEnabled = sliderEnabled
        slider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row.addArrangedSubview(slider)

        // FPS label
        let fpsLabel = createLabel(labelText, bold: true, size: 12)
        fpsLabel.tag = labelTag
        fpsLabel.textColor = sliderEnabled ? .labelColor : .disabledControlTextColor
        fpsLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        row.addArrangedSubview(fpsLabel)

        return row
    }

    /// Wraps a stack view in a scroll view for safe display on smaller windows.
    private func wrapInScrollView(_ contentStack: NSStackView) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.windowWidth, height: 620))

        // Flipped document view ensures content starts at top
        let flippedView = FlippedView()
        flippedView.translatesAutoresizingMaskIntoConstraints = false
        flippedView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: flippedView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: flippedView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: flippedView.trailingAnchor),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: flippedView.bottomAnchor),
        ])

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = flippedView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        containerView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            flippedView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])

        return containerView
    }
}

// MARK: - FlippedView

/// An NSView subclass that flips the coordinate system so content flows top-to-bottom.
/// Required for scroll views with Auto Layout stack views to display content from the top.
private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - NSView Tag Finder

extension NSView {
    /// Recursively finds a subview with the given tag in the entire view hierarchy.
    /// More reliable than `viewWithTag(_:)` which only searches immediate subviews on macOS.
    func findView(withTag tag: Int) -> NSView? {
        if self.tag == tag { return self }
        for subview in subviews {
            if let found = subview.findView(withTag: tag) {
                return found
            }
        }
        return nil
    }
}
