// An empty install tree under the temporary directory, for load-order tests
// that need real folders but no game data.

import Foundation
@testable import OpenSkyGameData

public struct TemporaryInstall {
    public let installURL: URL
    public let dataURL: URL

    /// Creates `<tmp>/<prefix>-<UUID>/Data/`.
    public init(prefix: String) throws {
        installURL = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .isDirectory)
        dataURL = installURL.appending(path: "Data", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    public var root: GameDataRoot {
        GameDataRoot(installURL: installURL, dataURL: dataURL, source: .environment)
    }

    /// Writes one empty marker file per name into `Data/`.
    public func touch(_ names: [String]) throws {
        for name in names {
            try Data().write(to: dataURL.appending(path: name, directoryHint: .notDirectory))
        }
    }
}
