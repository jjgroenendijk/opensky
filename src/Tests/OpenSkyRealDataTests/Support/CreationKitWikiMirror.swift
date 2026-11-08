import Foundation

/// The offline Creation Kit wiki mirror, `.cache/ck-wiki/` in the main checkout, which
/// every worktree shares. Nil when `make test-real` did not pass the checkout or the
/// mirror was never synced with `make ck-wiki`.
nonisolated enum CreationKitWikiMirror {
    static let directory: URL? = {
        guard let checkout = ProcessInfo.processInfo.environment["OPENSKY_CHECKOUT"] else {
            return nil
        }
        let root = URL(filePath: checkout, directoryHint: .isDirectory)
        for candidate in [root, mainCheckout(of: root)].compactMap(\.self) {
            let mirror = candidate.appending(path: ".cache/ck-wiki", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: mirror.appending(path: "index.md").path) {
                return mirror
            }
        }
        return nil
    }()

    static var isAvailable: Bool {
        directory != nil
    }

    /// A linked worktree's `.git` file reads `gitdir: <main>/.git/worktrees/<name>`.
    private static func mainCheckout(of worktree: URL) -> URL? {
        guard
            let text = try? String(contentsOf: worktree.appending(path: ".git"), encoding: .utf8),
            let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: "),
            let range = line.range(of: "/.git/worktrees/")
        else { return nil }
        let main = line[line.index(line.startIndex, offsetBy: 8) ..< range.lowerBound]
        return URL(filePath: String(main), directoryHint: .isDirectory)
    }
}
