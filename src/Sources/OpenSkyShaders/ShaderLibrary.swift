public import Foundation
public import Metal

/// The compiled shaders of this module, shipped as `default.metallib` in its resource bundle.
/// The app, openskycli, and every test load them from here.
nonisolated public enum ShaderLibrary {
    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missing

        public var description: String {
            "the shader library is missing: no \(bundleName).bundle next to the app, the tool, "
                + "or the test bundle"
        }
    }

    /// SwiftPM and Xcode both name the resource bundle `<package>_<target>`.
    static let bundleName = "OpenSky_OpenSkyShaders"

    /// The compiled library file, which also stamps the pipeline cache.
    public static let url: URL? = candidateFolders
        .lazy
        .map { $0.appending(path: "\(bundleName).bundle", directoryHint: .isDirectory) }
        .compactMap { Bundle(url: $0)?.url(forResource: "default", withExtension: "metallib") }
        .first

    public static func make(device: any MTLDevice) throws -> any MTLLibrary {
        guard let url else { throw LoadError.missing }
        return try device.makeLibrary(URL: url)
    }

    /// Xcode's generated `Bundle.module` traps when a test bundle links this module into a
    /// framework, so the lookup also tries the folder that holds the code and every loaded bundle.
    private static var candidateFolders: [URL] {
        let code = Bundle(for: BundleMarker.self)
        let near = [
            Bundle.main.resourceURL, code.resourceURL, Bundle.main.bundleURL,
            code.bundleURL.deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent()
        ]
        return near.compactMap(\.self) + (Bundle.allBundles + Bundle.allFrameworks)
            .compactMap(\.resourceURL)
    }
}

private final class BundleMarker {}
