// The perk sky's three meshes: parsed off the main actor, then given GPU buffers and
// textures on the first frame after. Kept for the session.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsMesh
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

    private let files: AssetLoader<String, NIFFile>
    private let fileSystem: any GameFileSource
    private var textures: TextureLibrary?
    public private(set) var models: Models?
    public private(set) var failure: String?

    /// `immediate` loads inside the request, for tests and tools.
    public init(fileSystem: any GameFileSource, immediate: Bool = false) {
        let load: @Sendable (String) throws -> NIFFile = { path in
            try NIFFile(data: fileSystem.contents(forPath: path))
        }
        files = immediate
            ? AssetLoader(worker: ImmediateAssetLoadWorker(load: load))
            : AssetLoader(load: load)
        self.fileSystem = fileSystem
    }

    /// The models once all three files are in; nil while they load or after a failure.
    public func models(device: MTLDevice) -> Models? {
        if models != nil || failure != nil {
            return models
        }
        for path in Self.paths {
            files.prefetch(path)
        }
        files.drain()
        var parsed: [NIFFile] = []
        for path in Self.paths {
            switch files.state(of: path) {
            case .loading: return nil
            case let .failed(error):
                failure = "\(path): \(error)"
                return nil
            case let .ready(file): parsed.append(file)
            }
        }
        do {
            let library = try textures ?? TextureLibrary(fileSystem: fileSystem, device: device)
            textures = library
            let built = try parsed.map {
                try MenuSceneModel(file: $0, device: device, textures: library.provider)
            }
            models = Models(dome: built[0], star: built[1], line: built[2])
        } catch {
            failure = String(describing: error)
        }
        return models
    }
}
