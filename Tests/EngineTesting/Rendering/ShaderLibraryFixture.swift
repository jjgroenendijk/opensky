// The shader library a package test hands to `Renderer`. The app and openskycli
// load `default.metallib` from their own bundle; a package test has no such
// bundle, so `make` compiles the shaders into one file first
// (`make shader-library`) and names it in OPENSKY_SHADER_LIBRARY.

import Foundation
import Metal

public enum ShaderLibraryFixtureError: Error, CustomStringConvertible {
    case environmentMissing
    case fileMissing(path: String)

    public var description: String {
        switch self {
        case .environmentMissing:
            "\(ShaderLibraryFixture.environmentKey) is not set. Run the tests through "
                + "`make test-unit`, which compiles the shaders and sets it."
        case let .fileMissing(path):
            "no shader library at \(path). Run `make shader-library`, or run the tests "
                + "through `make test-unit`."
        }
    }
}

@MainActor
public enum ShaderLibraryFixture {
    nonisolated public static let environmentKey = "OPENSKY_SHADER_LIBRARY"

    /// One library per device, loaded once per test process.
    private static var libraries: [UInt64: MTLLibrary] = [:]

    /// The compiled shaders for `device`. A missing variable or file throws,
    /// so the test fails with the reason instead of skipping.
    public static func library(device: MTLDevice) throws -> MTLLibrary {
        if let library = libraries[device.registryID] {
            return library
        }
        guard
            let path = ProcessInfo.processInfo.environment[environmentKey],
            !path.isEmpty
        else { throw ShaderLibraryFixtureError.environmentMissing }
        guard FileManager.default.fileExists(atPath: path) else {
            throw ShaderLibraryFixtureError.fileMissing(path: path)
        }
        let library = try device.makeLibrary(URL: URL(filePath: path))
        libraries[device.registryID] = library
        return library
    }
}
