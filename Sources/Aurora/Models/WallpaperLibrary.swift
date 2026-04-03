// Aurora — WallpaperLibrary
// JSON-based catalog for wallpaper metadata, per-display assignments, and state restoration.

import Foundation
import CoreGraphics

/// Manages the wallpaper catalog and per-display assignments.
/// Persists to ~/Library/Application Support/Aurora/library.json
final class WallpaperLibrary {

    // MARK: - Singleton

    static let shared = WallpaperLibrary()

    // MARK: - Paths

    /// Root storage directory.
    static var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Aurora", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory where imported wallpaper files are stored.
    static var wallpapersDir: URL {
        let dir = appSupportDir.appendingPathComponent("Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Directory for generated thumbnails.
    static var thumbnailsDir: URL {
        let dir = appSupportDir.appendingPathComponent("Thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Path to the library catalog JSON.
    private static var catalogPath: URL {
        return appSupportDir.appendingPathComponent("library.json")
    }

    /// Path to the display assignments JSON (for state restoration).
    private static var assignmentsPath: URL {
        return appSupportDir.appendingPathComponent("assignments.json")
    }

    // MARK: - State

    /// All wallpapers in the library.
    private(set) var wallpapers: [Wallpaper] = []

    // MARK: - Init

    private init() {
        loadCatalog()
    }

    // MARK: - CRUD

    /// Adds a new wallpaper to the library.
    func add(_ wallpaper: Wallpaper) {
        wallpapers.append(wallpaper)
        saveCatalog()
        AuroraLogger.engine.info("Added wallpaper '\(wallpaper.name, privacy: .public)' to library")
    }

    /// Removes a wallpaper by ID.
    @discardableResult
    func remove(id: UUID) -> Wallpaper? {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = wallpapers.remove(at: index)

        // Clean up files
        try? FileManager.default.removeItem(atPath: removed.filePath)
        if let thumbPath = removed.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbPath)
        }

        saveCatalog()
        AuroraLogger.engine.info("Removed wallpaper '\(removed.name, privacy: .public)' from library")
        return removed
    }

    /// Updates an existing wallpaper's metadata.
    func update(_ wallpaper: Wallpaper) {
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        wallpapers[index] = wallpaper
        saveCatalog()
    }

    /// Finds a wallpaper by ID.
    func wallpaper(withID id: UUID) -> Wallpaper? {
        return wallpapers.first(where: { $0.id == id })
    }

    /// Finds wallpapers matching a search query (name).
    func search(query: String) -> [Wallpaper] {
        guard !query.isEmpty else { return wallpapers }
        return wallpapers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Display Assignments (State Restoration)

    /// Saves a per-display wallpaper assignment.
    func saveAssignment(wallpaperID: UUID, displayID: CGDirectDisplayID) {
        var assignments = loadAssignments()
        assignments[String(displayID)] = wallpaperID
        saveAssignments(assignments)
    }

    /// Loads all per-display wallpaper assignments.
    func loadAssignments() -> [String: UUID] {
        guard let data = try? Data(contentsOf: Self.assignmentsPath),
              let assignments = try? JSONDecoder().decode([String: UUID].self, from: data) else {
            return [:]
        }
        return assignments
    }

    /// Saves all per-display wallpaper assignments.
    private func saveAssignments(_ assignments: [String: UUID]) {
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        try? data.write(to: Self.assignmentsPath, options: .atomic)
    }

    /// Clears the assignment for a display.
    func clearAssignment(for displayID: CGDirectDisplayID) {
        var assignments = loadAssignments()
        assignments.removeValue(forKey: String(displayID))
        saveAssignments(assignments)
    }

    // MARK: - Catalog Persistence

    /// Loads the wallpaper catalog from disk.
    private func loadCatalog() {
        guard let data = try? Data(contentsOf: Self.catalogPath),
              let decoded = try? JSONDecoder().decode([Wallpaper].self, from: data) else {
            AuroraLogger.engine.info("No existing library catalog found, starting fresh")
            wallpapers = []
            return
        }

        // Filter out wallpapers whose files no longer exist
        wallpapers = decoded.filter { wallpaper in
            if !wallpaper.fileExists {
                AuroraLogger.engine.info("Wallpaper '\(wallpaper.name, privacy: .public)' file missing, removing from catalog")
                return false
            }
            return true
        }

        AuroraLogger.engine.info("Loaded \(self.wallpapers.count) wallpaper(s) from library")
    }

    /// Saves the wallpaper catalog to disk.
    private func saveCatalog() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(wallpapers) else {
            AuroraLogger.logFailure("Failed to encode wallpaper catalog")
            return
        }

        do {
            try data.write(to: Self.catalogPath, options: .atomic)
            AuroraLogger.engine.debug("Catalog saved (\(self.wallpapers.count) wallpapers)")
        } catch {
            AuroraLogger.logFailure("Failed to write catalog: \(error.localizedDescription)")
        }
    }
}
