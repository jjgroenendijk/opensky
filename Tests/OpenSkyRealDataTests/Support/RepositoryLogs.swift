import Foundation

/// The checkout's gitignored `logs/` directory. `#filePath` reads `/^src/...`
/// under the compilation cache, and the host's working directory is `/`, so
/// this walks up from the test bundle to the folder with `OpenSky.xcodeproj`.
enum RepositoryLogs {
    struct CheckoutNotFound: Error, CustomStringConvertible {
        let bundle: URL

        var description: String {
            "no OpenSky.xcodeproj above the test bundle at \(bundle.path); "
                + "real-data runs need the derived data inside the checkout"
        }
    }

    /// `<checkout>/logs`, or `<checkout>/logs/<subpath>` when a subpath is given.
    static func directory(_ subpath: String = "") throws -> URL {
        let bundle = Bundle(for: BundleToken.self).bundleURL
        var candidate = bundle.deletingLastPathComponent()
        while candidate.path != "/" {
            let project = candidate.appending(path: "OpenSky.xcodeproj")
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
