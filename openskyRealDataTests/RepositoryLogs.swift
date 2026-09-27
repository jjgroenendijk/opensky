import Foundation

/// The checkout's gitignored `logs/` directory, where real-data suites leave
/// reports and captures.
///
/// `#filePath` cannot name it: `Config/Debug.xcconfig` turns on the
/// compilation cache's prefix mapping, which compiles every source path to
/// `/^src/...`. The working directory cannot either, because the test host's is
/// `/`. The test bundle itself is built into the checkout's derived data
/// (`<checkout>/DerivedData/Build/Products/...`), so the checkout is the nearest
/// ancestor of the bundle that holds `opensky.xcodeproj`.
enum RepositoryLogs {
    struct CheckoutNotFound: Error, CustomStringConvertible {
        let bundle: URL

        var description: String {
            "no opensky.xcodeproj above the test bundle at \(bundle.path); "
                + "real-data runs need the derived data inside the checkout"
        }
    }

    /// `<checkout>/logs`, or `<checkout>/logs/<subpath>` when a subpath is given.
    static func directory(_ subpath: String = "") throws -> URL {
        let bundle = Bundle(for: BundleToken.self).bundleURL
        var candidate = bundle.deletingLastPathComponent()
        while candidate.path != "/" {
            let project = candidate.appending(path: "opensky.xcodeproj")
            if FileManager.default.fileExists(atPath: project.path) {
                let logs = candidate.appending(path: "logs", directoryHint: .isDirectory)
                return subpath.isEmpty
                    ? logs : logs.appending(path: subpath, directoryHint: .isDirectory)
            }
            candidate = candidate.deletingLastPathComponent()
        }
        throw CheckoutNotFound(bundle: bundle)
    }

    private final class BundleToken {}
}
