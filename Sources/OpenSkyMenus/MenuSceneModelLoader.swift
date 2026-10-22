// A fixed set of menu-scene meshes from the install: parsed off the main actor, then
// given GPU buffers and textures on the first frame after. Kept once built.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering

public final class MenuSceneModelLoader {
    public let paths: [String]
    private let files: AssetLoader<String, NIFFile>
    private let fileSystem: any GameFileSource
    private var textures: TextureLibrary?
    public private(set) var models: [MenuSceneModel]?
    public private(set) var failure: String?

    /// `immediate` loads inside the request, for tests and tools.
    public init(paths: [String], fileSystem: any GameFileSource, immediate: Bool = false) {
        let load: @Sendable (String) throws -> NIFFile = { path in
            try NIFFile(data: fileSystem.contents(forPath: path))
        }
        files = immediate
            ? AssetLoader(worker: ImmediateAssetLoadWorker(load: load))
            : AssetLoader(load: load)
        self.paths = paths
        self.fileSystem = fileSystem
    }

    /// The models in `paths` order once every file is in; nil while they load or after
    /// a failure.
    public func models(device: MTLDevice) -> [MenuSceneModel]? {
        if models != nil || failure != nil {
            return models
        }
        for path in paths {
            files.prefetch(path)
        }
        files.drain()
        var parsed: [NIFFile] = []
        for path in paths {
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
            models = try parsed.map {
                try MenuSceneModel(file: $0, device: device, textures: library.provider)
            }
        } catch {
            failure = String(describing: error)
        }
        return models
    }
}
