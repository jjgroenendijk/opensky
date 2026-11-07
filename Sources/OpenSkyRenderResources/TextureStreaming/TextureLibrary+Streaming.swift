// The loader half of texture streaming: a large texture becomes a sparse texture that
// starts with its small levels, and its larger levels can be read again on request.
// See docs/rendering/texture-streaming.md.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyGameData

nonisolated extension TextureLibrary {
    /// Nil when streaming is off or the texture does not stream.
    func streamedTexture(
        ready: ReadyTexture,
        path: String,
        usage: TextureUsage
    ) -> any MTLTexture? {
        guard let streaming, streaming.loadSettings.enabled else { return nil }
        let settings = streaming.loadSettings
        guard
            let sparse = loader.sparseTexture(
                ready: ready, usage: usage, label: path, settings: settings
            )
        else { return nil }
        let start = sparse.layout.level(fittingWithin: settings.initialSize)
        streaming.post(StreamedTextureSeed(
            texture: sparse.texture,
            source: TextureStreamSource(path: path, usage: usage),
            layout: sparse.layout,
            levels: TextureLevelBytes.levels(of: ready, from: start)
        ))
        return sparse.texture
    }

    /// The levels a streamed texture starts from, when streaming is on.
    func streamingReady(_ source: TextureSource) -> ReadyTexture? {
        guard let streaming, streaming.loadSettings.enabled else { return nil }
        return source.ready
    }

    /// Reads the levels of `request` again. Runs on the build worker.
    public func readLevels(_ request: TextureLevelRequest) -> TextureLevelBytes? {
        source(forPath: request.source.path).ready.map {
            TextureLevelBytes.levels(of: $0, from: request.firstLevel)
        }
    }
}
