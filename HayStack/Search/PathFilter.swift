import Foundation

struct PathFilterSettings: Sendable {
    let searchScope: SearchScope
    let excludedDirectories: [String]
}

struct PathFilter {
    static let blockedPathFragments: [String] = [
        "/Library/",
        "/System/",
        "/Applications/",
        "/usr/",
        "/private/",
        "/.Trash/",
        "/node_modules/",
        "/.git/",
        "/venv/",
        "/.venv/",
        "/env/",
        "/__pycache__/",
        "/.cache/",
        "/Cache/",
        "/Caches/",
        "/Application Support/",
        "/BrowserProfiles/",
        "/DerivedData/",
    ]

    static let blockedExtensions: Set<String> = [
        ".dylib", ".so", ".o", ".a",
        ".app", ".framework",
        ".log", ".pid", ".lock",
        ".ds_store",
        ".plist",
        ".sqlite", ".db",
    ]

    static func shouldInclude(_ path: String, settings: PathFilterSettings) -> Bool {
        let normalized = (path as NSString).standardizingPath
        let lowercased = normalized.lowercased()

        if settings.searchScope == .homeDirectory {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            guard lowercased.hasPrefix(home.lowercased()) else { return false }
        }

        for excluded in settings.excludedDirectories {
            let excludedPath = (excluded as NSString).standardizingPath.lowercased()
            if lowercased.hasPrefix(excludedPath) { return false }
        }

        for fragment in blockedPathFragments {
            if lowercased.contains(fragment.lowercased()) { return false }
        }

        let ext = (normalized as NSString).pathExtension.lowercased()
        if !ext.isEmpty, blockedExtensions.contains(".\(ext)") { return false }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory) else {
            return false
        }
        if isDirectory.boolValue { return false }

        return true
    }

    static func filter(_ paths: [String], settings: PathFilterSettings, limit: Int = 100) -> [String] {
        var results: [String] = []
        results.reserveCapacity(min(paths.count, limit))

        for path in paths {
            guard shouldInclude(path, settings: settings) else { continue }
            results.append(path)
            if results.count >= limit { break }
        }

        return results
    }
}
