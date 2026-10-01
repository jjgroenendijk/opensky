import Foundation
import Metal
@testable import OpenSkyGameData

/// The install and GPU a gated suite runs against, resolved once per test run.
nonisolated enum RealDataEnvironment {
    /// Only `OPENSKY_DATA_ROOT` opens the install, so a machine without it skips.
    static let dataRoot: GameDataRoot? = {
        let path = ProcessInfo.processInfo.environment[GameDataLocator.environmentKey]
        guard let path, !path.isEmpty else { return nil }
        return try? GameDataLocator.locate()
    }()

    static let device: (any MTLDevice)? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    static var hasDataRoot: Bool {
        dataRoot != nil
    }

    static var canRender: Bool {
        dataRoot != nil && device != nil
    }
}
