// Builds preview scenes off the main actor for the app. It owns one cell builder, so
// its mesh and texture caches last across previews; one build runs at a time.

import Foundation
import Metal
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorld
import Synchronization

/// One built scene, with the sources the main actor renders it with.
nonisolated public struct PreviewSceneResult: Sendable {
    public let scene: PreviewScene
    public let loadOrder: LoadOrderPlugins
    public let fileSystem: (any GameFileSource)?
}

nonisolated public final class PreviewSceneWorker: Sendable {
    private let root: GameDataRoot
    private let device: any MTLDevice
    private let settings: Data?
    private let builder = Mutex<PreviewSceneBuilder?>(nil)

    /// `settings` are the saved player settings, read on the main actor.
    public init(root: GameDataRoot, device: any MTLDevice, settings: Data?) {
        self.root = root
        self.device = device
        self.settings = settings
    }

    @concurrent
    public func build(_ request: PreviewRequest) async -> Result<PreviewSceneResult, PreviewError> {
        builder.withLock { stored in
            do {
                let builder = try stored ?? makeBuilder()
                stored = builder
                let scene = try builder.build(request)
                return .success(PreviewSceneResult(
                    scene: scene,
                    loadOrder: builder.builder.pluginLoadOrder,
                    fileSystem: builder.builder.fileSystem
                ))
            } catch let error as PreviewError {
                return .failure(error)
            } catch {
                return .failure(.cellFailed(String(describing: error)))
            }
        }
    }

    private func makeBuilder() throws -> PreviewSceneBuilder {
        let files = VirtualFileSystem(root: root)
        let builder = try StandardBenchmark.makeBuilder(
            loadOrder: ActiveLoadOrder.open(root: root), files: files, device: device,
            recorder: nil,
            terrainLOD: StandardBenchmark.terrainLODStore(root: root, settings: settings)
        )
        return PreviewSceneBuilder(builder: builder)
    }
}
