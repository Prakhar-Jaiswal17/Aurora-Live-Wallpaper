// Aurora — macOS Live Wallpaper Engine
// Entry point: creates NSApplication, sets delegate, runs event loop.

import AppKit

// Create the shared application instance
let app = NSApplication.shared

// Configure as accessory app (no Dock icon, menu bar only)
app.setActivationPolicy(.accessory)

// Set the app delegate
let delegate = AppDelegate()
app.delegate = delegate

// Run the application event loop
app.run()
