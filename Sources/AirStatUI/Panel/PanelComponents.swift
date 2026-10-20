import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AirStatKit

// MARK: - Process icons

/// What to draw beside a process name.
enum PanelProcessIcon {
    case bundle(NSImage)
    /// No bundle to take an icon from — most processes, since launchd, logd and
    /// WindowServer are plain executables.
    case executable
}

/// Icons for the process list.
///
/// Every row resolves to something, so the list has one left edge. Half the rows
/// carrying an icon and half not is worse than either choice made consistently.
///
/// `NSWorkspace.icon(forFile:)` stats the bundle, so it is resolved once per
/// executable path and never again — including the misses, so a daemon does not
/// re-hit the filesystem every time the panel redraws.
@MainActor
enum PanelAppIcon {
    private static var cache: [String: PanelProcessIcon] = [:]

    /// The cache is keyed by executable path, and the set of paths a long session sees
    /// is not the set of apps installed: every build tool, helper and short-lived daemon
    /// that ever reached the top of the process list adds one and nothing ever took one
    /// away. 224 icons measured at 3.1 MB of dirty heap, so an uncapped cache is real
    /// growth over a day of uptime. Flushed wholesale rather than evicted one at a time —
    /// the next panel redraw re-resolves only the dozen rows it actually shows, and that
    /// is cheaper than tracking use counts for the life of the process.
    private static let cacheLimit = 512

    static func icon(for process: ProcessRow) -> PanelProcessIcon {
        guard let path = process.executablePath else { return .executable }
        if let cached = cache[path] { return cached }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        let resolved: PanelProcessIcon
        if let bundle = bundlePath(for: path), FileManager.default.fileExists(atPath: bundle) {
            resolved = .bundle(NSWorkspace.shared.icon(forFile: bundle))
        } else {
            resolved = .executable
        }
        cache[path] = resolved
        return resolved
    }

    /// The enclosing app bundle: "/Applications/Claude.app/Contents/Frameworks/Claude"
    /// → "/Applications/Claude.app".
    ///
    /// A running process's executable is almost never the bundle itself — it lives
    /// several directories inside one — so testing the path for a ".app" suffix
    /// resolves nothing on a real machine. Taking the first ".app" component also gets
    /// helpers right: Safari's XPC services correctly show Safari's icon.
    private static func bundlePath(for path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return path.hasSuffix(".app") ? path : nil
        }
        return String(path[path.startIndex..<range.lowerBound]) + ".app"
    }
}
