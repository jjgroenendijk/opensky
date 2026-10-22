// The perk sky's three meshes: parsed off the main actor, then given GPU buffers and
// textures on the first frame after. Kept for the session.

import Foundation
@preconcurrency import Metal
import OpenSkyGameData
import OpenSkyRendering

public final class PerkSkySource {
    public static let domePath = "meshes\\interface\\intperkskydome.nif"
    public static let starPath = "meshes\\interface\\intperkstars01.nif"
    public static let linePath = "meshes\\interface\\intperkline01.nif"
    static let paths = [domePath, starPath, linePath]

    public struct Models {
        public let dome: MenuSceneModel
        public let star: MenuSceneModel
        public let line: MenuSceneModel
    }

    private let loader: MenuSceneModelLoader

    /// `immediate` loads inside the request, for tests and tools.
    public init(fileSystem: any GameFileSource, immediate: Bool = false) {
        loader = MenuSceneModelLoader(
            paths: Self.paths, fileSystem: fileSystem, immediate: immediate
        )
    }

    public var models: Models? {
        loader.models.map { Models(dome: $0[0], star: $0[1], line: $0[2]) }
    }

    public var failure: String? {
        loader.failure
    }

    /// The models once all three files are in; nil while they load or after a failure.
    public func models(device: MTLDevice) -> Models? {
        loader.models(device: device).map { Models(dome: $0[0], star: $0[1], line: $0[2]) }
    }
}
