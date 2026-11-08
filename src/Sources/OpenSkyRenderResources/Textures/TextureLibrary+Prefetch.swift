// Prepares a cell build's new textures on every core before its models ask for them
// (docs/decisions/concurrency.md). Workers read, look up, parse, and fill textures;
// streaming, the fast loader, the cache, and every counter stay on the build thread.

public import Foundation
@preconcurrency @unsafe public import Metal
public import OpenSkyAssetCache
public import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData

/// Where a texture's bytes come from.
nonisolated enum TextureSource: Sendable {
    case cached(AssetCacheEntryRead<ReadyTexture>)
    case archive(Data)
    case missing

    /// The levels as a cached texture holds them; nil for a file that does not parse.
    var ready: ReadyTexture? {
        switch self {
        case let .cached(entry): entry.value
        case let .archive(data): attempt { try DDSFile(data: data) }.map(ReadyTexture.init(dds:))
        case .missing: nil
        }
    }

    var declaresVolume: Bool {
        guard case let .archive(data) = self else { return false }
        return DDSFile.declaresVolume(data)
    }
}

/// A texture's source, and the work a decode worker already did on it.
nonisolated struct PreparedTexture: Sendable {
    let source: TextureSource
    /// Filled on the CPU; the load only counts it.
    var uploaded: any MTLTexture?
    /// The levels for a texture that may stream, so the load does not convert them again.
    var streamReady: ReadyTexture?
}

nonisolated extension TextureLibrary {
    private struct Request: Hashable {
        let path: String
        let usage: TextureUsage
    }

    /// Prepares the colour and data maps of `materials` that are not loaded yet.
    public func prefetch(materials: [Material]) {
        guard decodesInParallel else { return }
        let requests = newRequests(materials)
        guard requests.count >= ParallelDecode.minimumParallelItems else { return }
        loadPhases.measure(.texture) { prepare(requests) }
    }

    /// Frees prepared textures no load asked for, such as those of a model that failed.
    public func dropPrefetched() {
        prefetched.removeAll()
    }

    private func newRequests(_ materials: [Material]) -> [Request] {
        var requests: [Request] = []
        var seen = Set<Request>()
        let record: TextureProvider = { [self] key, usage in
            let usage = usage == .effectSource ? .color : usage
            if
                let key, usage == .color || usage == .data,
                let path = attempt({ try VirtualFileSystem.normalize(key) })
            {
                let request = Request(path: path, usage: usage)
                let key = CacheKey(path: path, usage: usage)
                if cache[key] == nil, prefetched[key] == nil, seen.insert(request).inserted {
                    requests.append(request)
                }
            }
            return loader.placeholder(usage: usage)
        }
        for material in materials {
            _ = RenderMaterial(material: material, textureProvider: record)
        }
        return requests
    }

    private func prepare(_ requests: [Request]) {
        let cacheReader = assetCache
        let files = fileSystem.untimed
        let sources = ParallelDecode.map(Set(requests.map(\.path))) { path -> TextureSource? in
            if let entry = cacheReader?.entry(forPath: path, decoder: .readyTexture) {
                return .cached(entry)
            }
            guard let data = attempt({ try files.contents(forPath: path) }) else { return .missing }
            return .archive(data)
        }
        let fastFiles = Set(sources.values.compactMap { source -> URL? in
            guard case let .cached(entry) = source, readsFast(entry) else { return nil }
            return entry.file
        })
        let plan = UploadPlan(
            device: loader.device, streaming: streaming?.loadSettings, fastFiles: fastFiles
        )
        let prepared = ParallelDecode.map(requests) { [sources] request -> PreparedTexture? in
            sources[request.path].map { plan.prepare($0, path: request.path, usage: request.usage) }
        }
        for (request, texture) in prepared {
            prefetched[CacheKey(path: request.path, usage: request.usage)] = texture
        }
    }
}

/// What a worker may do to one source without the build thread's state.
nonisolated private struct UploadPlan: Sendable {
    let device: any MTLDevice
    let streaming: TextureStreamingLoadSettings?
    let fastFiles: Set<URL>

    func prepare(_ source: TextureSource, path: String, usage: TextureUsage) -> PreparedTexture {
        var prepared = PreparedTexture(source: source)
        if streaming?.enabled == true, let ready = source.ready, mayStream(ready) {
            prepared.streamReady = ready
            return prepared
        }
        switch source {
        case let .cached(entry) where !fastFiles.contains(entry.file):
            prepared.uploaded = attempt {
                try TextureLoader.upload(
                    ready: entry.value, usage: usage, label: path, device: device
                )
            }
        case let .archive(data):
            prepared.uploaded = attempt {
                try Self.upload(
                    dds: data,
                    usage: usage,
                    label: path,
                    device: device
                )
            }
        case .cached, .missing:
            break
        }
        return prepared
    }

    /// The size test of `TextureLoader.sparseTexture`; the load makes the sparse texture.
    private func mayStream(_ ready: ReadyTexture) -> Bool {
        guard let streaming else { return false }
        return ready.mipCount > 1 && max(ready.width, ready.height) >= streaming.minimumSize
    }

    /// A failure leaves the upload to the load, which logs it and uses the placeholder.
    private static func upload(
        dds data: Data, usage: TextureUsage, label: String, device: any MTLDevice
    ) throws -> any MTLTexture? {
        let dds = try DDSFile(data: data)
        guard dds.faceCount == 1 else { return nil }
        return try TextureLoader.upload(dds: dds, usage: usage, label: label, device: device)
    }
}
