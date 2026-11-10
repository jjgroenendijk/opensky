// The perk sky's three meshes: parsed off the main actor, then given GPU buffers and
// textures on the first frame after. Kept for the session.

import Foundation
@preconcurrency @unsafe import Metal
public import OpenSkyGameData
public import OpenSkyRendering

public final class PerkSkySource {
    static let domePath = "meshes\\interface\\intperkskydome.nif"
    static let starPath = "meshes\\interface\\intperkstars01.nif"
    static let linePath = "meshes\\interface\\intperkline01.nif"
    static let paths = [domePath, starPath, linePath]

    struct Models {
        let dome: MenuSceneModel
        let star: MenuSceneModel
        let line: MenuSceneModel
    }

    private let loader: MenuSceneModelLoader

    /// `immediate` loads inside the request, for tests and tools.
    public init(fileSystem: any GameFileSource, immediate: Bool = false) {
        loader = MenuSceneModelLoader(
            paths: Self.paths, fileSystem: fileSystem, immediate: immediate
        )
    }

    var failure: String? {
        loader.failure
    }

    /// The models once all three files are in; nil while they load or after a failure.
    func models(device: any MTLDevice) -> Models? {
        loader.models(device: device).map { Models(dome: $0[0], star: $0[1], line: $0[2]) }
    }
}
