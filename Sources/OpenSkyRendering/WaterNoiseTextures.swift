// The WATR noise normal maps (`NAM2`-`NAM4`). They load off the main actor; the frame
// drains them and keeps the GPU copies (docs/rendering/water.md#surface).

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRenderResources

public final class WaterNoiseTextures {
    private let loader: AssetLoader<String, Data>
    private let textureLoader: TextureLoader
    private var textures: [String: MTLTexture] = [:]
    public private(set) var failedPaths: [String] = []

    /// `immediate` loads inside the request, for offscreen frames and tests.
    public init(fileSystem: any GameFileSource, device: MTLDevice, immediate: Bool = false) throws {
        let load: @Sendable (String) throws -> Data = { try fileSystem.contents(forPath: $0) }
        loader = immediate
            ? AssetLoader(worker: ImmediateAssetLoadWorker(load: load))
            : AssetLoader(load: load)
        textureLoader = try TextureLoader(device: device)
    }

    /// The record writes `Data\Textures\...`; the file system starts below `Data\`.
    nonisolated public static func filePath(_ recordPath: String) -> String? {
        var path = recordPath.replacingOccurrences(of: "/", with: "\\")
        guard !path.isEmpty else { return nil }
        if path.lowercased().hasPrefix("data\\") {
            path.removeFirst(5)
        }
        return (try? VirtualFileSystem.normalize(path)) ?? path.lowercased()
    }

    /// The three layer maps of `paths`, or nil while any is missing or loading.
    func layers(_ paths: [String]) -> [MTLTexture]? {
        guard paths.count >= 3 else { return nil }
        let maps = paths.prefix(3).compactMap { Self.filePath($0).flatMap { textures[$0] } }
        return maps.count == 3 ? maps : nil
    }

    /// Moves finished loads in and asks for what `paths` needs. Returns new GPU
    /// allocations, which the caller makes resident.
    func prepare(_ paths: Set<String>) -> [MTLAllocation] {
        for path in paths.compactMap(Self.filePath) where textures[path] == nil {
            loader.prefetch(path)
        }
        var added: [MTLAllocation] = []
        for path in loader.drain() {
            switch loader.state(of: path) {
            case let .ready(data):
                let texture = textureLoader.texture(dds: data, usage: .data, label: path)
                textures[path] = texture
                added.append(texture)
            case let .failed(failure):
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
    public func prepareWaterTextures() {
        guard let waterNoiseTextures, !scene.water.isEmpty else { return }
        let paths = Set(scene.water.flatMap(\.look.shading.noiseTextures).filter { !$0.isEmpty })
        let added = waterNoiseTextures.prepare(paths)
        guard !added.isEmpty else { return }
        residencySet.addAllocations(added)
        residencySet.commit()
    }
}
