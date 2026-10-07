// The loader half of texture streaming: a large texture becomes a sparse texture that
// starts with its small levels, and its larger levels can be read again on request.
// See docs/rendering/texture-streaming.md.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyFormatsMesh
import OpenSkyGameData

nonisolated extension TextureLibrary {
    /// Nil when streaming is off or the texture does not stream.
    func streamedTexture(path: String, usage: TextureUsage) -> MTLTexture? {
        guard let streaming, streaming.loadSettings.enabled else { return nil }
        let settings = streaming.loadSettings
        guard
            let ready = readyTexture(path: path),
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

    /// Reads the levels of `request` again. Runs on the build worker.
    public func readLevels(_ request: TextureLevelRequest) -> TextureLevelBytes? {
        readyTexture(path: request.source.path).map {
            TextureLevelBytes.levels(of: $0, from: request.firstLevel)
        }
    }

    /// The levels from the asset cache when it holds them, else from the archives.
    private func readyTexture(path: String) -> ReadyTexture? {
        if let ready = assetCache?.value(forPath: path, decoder: .readyTexture) {
            return ready
        }
        guard
            let data = try? fileSystem.contents(forPath: path),
            let dds = try? DDSFile(data: data)
        else { return nil }
        return ReadyTexture(dds: dds)
    }
}

/// Reads levels on the calling thread. For the CLI and tests, where loads run in line.
nonisolated public final class InlineTextureLevelReader: TextureLevelReading {
    private let library: TextureLibrary

    public init(library: TextureLibrary) {
        self.library = library
    }

    public func requestTextureLevels(
        _ request: TextureLevelRequest,
        mailbox: TextureStreamMailbox
    ) {
        if let levels = library.readLevels(request) {
            mailbox.post(levels: levels, for: request.texture)
        }
    }
}
