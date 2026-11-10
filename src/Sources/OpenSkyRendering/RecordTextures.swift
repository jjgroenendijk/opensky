// Textures a record names by path, such as the WATR noise maps (`NAM2`-`NAM4`) and the
// SPGD particle textures. They load off the main actor; the frame drains them and keeps
// the GPU copies (docs/rendering/water.md#surface).

import Foundation
public import Metal
import OpenSkyFormatsCore
public import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRenderResources

public final class RecordTextures {
    private let loader: AssetLoader<String, Data>
    private let textureLoader: TextureLoader
    private var textures: [String: any MTLTexture] = [:]
    /// How each requested path decodes; a path not listed is data.
    private var usages: [String: TextureUsage] = [:]
    private var missing: Set<String> = []
    public private(set) var failedPaths: [String] = []

    /// `immediate` loads inside the request, for offscreen frames and tests.
    public init(
        fileSystem: any GameFileSource,
        device: any MTLDevice,
        immediate: Bool = false
    ) throws {
        let load: @Sendable (String) throws -> Data = { try fileSystem.contents(forPath: $0) }
        loader = immediate
            ? AssetLoader(worker: ImmediateAssetLoadWorker(load: load))
            : AssetLoader(load: load)
        textureLoader = try TextureLoader(device: device)
    }

    /// The record writes `Data\Textures\...`; the file system starts below `Data\`.
    nonisolated static func filePath(_ recordPath: String) -> String? {
        var path = recordPath.replacingOccurrences(of: "/", with: "\\")
        guard !path.isEmpty else { return nil }
        if path.lowercased().hasPrefix("data\\") {
            path.removeFirst(5)
        }
        return attempt { try VirtualFileSystem.normalize(path) } ?? path.lowercased()
    }

    /// The three layer maps of `paths`, or nil while any is missing or loading.
    func layers(_ paths: [String]) -> [any MTLTexture]? {
        guard paths.count >= 3 else { return nil }
        let maps = paths.prefix(3).compactMap { Self.filePath($0).flatMap { textures[$0] } }
        return maps.count == 3 ? maps : nil
    }

    /// One loaded map, such as a cell's flow map, or nil while it loads.
    func texture(_ path: String) -> any MTLTexture? {
        Self.filePath(path).flatMap { textures[$0] }
    }

    /// Moves finished loads in and asks for what `paths` needs. Returns new GPU
    /// allocations, which the caller makes resident.
    func prepare(_ paths: Set<String>, usage: TextureUsage = .data) -> [any MTLAllocation] {
        for path in paths.compactMap(Self.filePath)
            where textures[path] == nil && !missing.contains(path)
        {
            usages[path] = usage
            loader.prefetch(path)
        }
        var added: [any MTLAllocation] = []
        for path in loader.drain() {
            switch loader.state(of: path) {
            case let .ready(data):
                let texture = textureLoader.texture(
                    dds: data, usage: usages[path] ?? .data, label: path
                )
                textures[path] = texture
                added.append(texture)
            case let .failed(failure):
                missing.insert(path)
                failedPaths.append("\(path): \(failure)")
            case .loading:
                break
            }
        }
        loader.evict { _ in true }
        return added
    }
}

extension Renderer {
    /// Drains finished noise map loads and requests the maps of the water in the scene.
    func prepareWaterTextures() {
        guard let recordTextures, !scene.water.isEmpty else { return }
        let paths = Set(scene.water.flatMap { item in
            item.look.shading.noiseTextures + [item.look.shading.flowNoiseTexture]
                + (item.flowMap.map { [$0] } ?? [])
        }.filter { !$0.isEmpty })
        let added = recordTextures.prepare(paths)
        guard !added.isEmpty else { return }
        residencySet.addAllocations(added)
        residencySet.commit()
    }

    /// Each water plane's flow map in the scene, and whether it and its flow noise loaded.
    public func waterFlowMaps() -> [(path: String, loaded: Bool)] {
        scene.water.compactMap { item in
            item.flowMap.map { path in
                let loaded = recordTextures?.texture(path) != nil
                    && recordTextures?.texture(item.look.shading.flowNoiseTexture) != nil
                return (path, loaded)
            }
        }
    }
}
