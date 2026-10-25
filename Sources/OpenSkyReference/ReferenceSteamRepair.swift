// Two repairs Windows Steam needs under Wine before each start
// (docs/tools/reference-game.md): a Steam update puts Valve's web helper back in place
// of the wrapper, and a crash leaves Chromium lock files that make the next start
// windowless.

import Foundation

nonisolated public enum ReferenceSteamRepair {
    /// Valve's helper is tens of megabytes; the wrapper is a few kilobytes.
    static let wrapperSizeLimit = 500_000
    static let helperName = "steamwebhelper.exe"
    static let realHelperName = "steamwebhelper_real.exe"

    /// Moves Valve's helper to `steamwebhelper_real.exe` and puts the wrapper in its
    /// place, in each `cef.win*` folder. Returns the folders it changed.
    @discardableResult
    public static func deployWrapper(prefix: ReferencePrefix) throws -> Int {
        let files = FileManager.default
        guard files.fileExists(atPath: prefix.webHelperWrapper.path(percentEncoded: false)) else {
            throw ReferenceLauncherError.noWrapper
        }
        let folders = (try? files.contentsOfDirectory(
            at: prefix.cefDirectory, includingPropertiesForKeys: nil
        )) ?? []
        var changed = 0
        for folder in folders where folder.lastPathComponent.hasPrefix("cef.win") {
            let helper = folder.appending(path: helperName)
            let size = (try? helper.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size > wrapperSizeLimit else { continue }
            let real = folder.appending(path: realHelperName)
            try? files.removeItem(at: real)
            try files.moveItem(at: helper, to: real)
            try files.copyItem(at: prefix.webHelperWrapper, to: helper)
            changed += 1
        }
        return changed
    }

    /// Deletes `Singleton*` and `*.lock` files up to one folder below each Wine user's
    /// Steam `htmlcache`. Returns how many it deleted.
    @discardableResult
    public static func removeBrowserLocks(prefix: ReferencePrefix) -> Int {
        let files = FileManager.default
        let users = prefix.driveC.appending(path: "users", directoryHint: .isDirectory)
        let caches = ((try? files.contentsOfDirectory(at: users, includingPropertiesForKeys: nil))
            ?? []).map { $0.appending(path: "AppData/Local/Steam/htmlcache") }
        var folders = caches
        for cache in caches {
            folders += (try? files.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil))
                ?? []
        }
        var removed = 0
        for folder in folders {
            let entries = (try? files.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil
            ))
                ?? []
            for entry in entries where isLock(entry.lastPathComponent) {
                if (try? files.removeItem(at: entry)) != nil {
                    removed += 1
                }
            }
        }
        return removed
    }

    static func isLock(_ name: String) -> Bool {
        name.hasPrefix("Singleton") || name.hasSuffix(".lock")
    }
}
