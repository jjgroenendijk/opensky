// The asset cache, loose file, and fast loading options the benchmarks share:
// `--asset-cache`, `--fast-load`, `--fast-mesh-load`, `--evict`, `--loose <dir>`, `--record-paths
// <file>`,
// and the cache settings options of `asset-cache`.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld

struct AssetLoadOptions {
    let cache: AssetCacheReader?
    let looseFolder: URL?
    let recordPath: String?
    let fastLoad: Bool
    let fastMeshLoad: Bool

    init(scanner: inout ArgumentScanner, context: CLIContext) throws {
        let useCache = scanner.flag("--asset-cache")
        let evict = scanner.flag("--evict")
        fastLoad = scanner.flag("--fast-load")
        fastMeshLoad = scanner.flag("--fast-mesh-load")
        let loose = try scanner.option("--loose")
        looseFolder = loose.map { URL(filePath: $0, directoryHint: .isDirectory) }
        recordPath = try scanner.option("--record-paths")
        let settings = try AssetCacheCommand.settings(scanner: &scanner)
        guard useCache || !(fastLoad || fastMeshLoad) else {
            throw CLIError.usage("--fast-load and --fast-mesh-load need --asset-cache")
        }
        cache = try useCache ? AssetCacheReader.open(
            settings: settings, files: context.makeFileSystem(),
            gameInstall: context.root.installURL
        ) : nil
        if evict {
            let folders = [context.root.dataURL] + [cache?.store.root, looseFolder]
                .compactMap(\.self)
            let evicted = PageCacheEviction.evict(folders: folders)
            print("[INFO] evicted \(evicted >> 20) MiB from the page cache")
        }
    }

    /// Points the builder's libraries at the cache and the fast loader.
    func configure(_ builder: CellSceneBuilder, device: MTLDevice) throws {
        builder.textures.assetCache = cache
        builder.meshes.assetCache = cache
        builder.collisionModels?.assetCache = cache
        if fastLoad || fastMeshLoad {
            builder.textures.fastLoader = try FastTextureLoader(
                device: device,
                control: FastTextureLoadControl(isEnabled: fastLoad, loadsMeshes: fastMeshLoad)
            )
        }
    }

    func report(fastLoader: FastTextureLoader?) throws {
        guard let cache else { return }
        for kind in [AssetCacheKind.texture, .mesh] {
            let counts = cache.counts(for: kind)
            print("[INFO] asset cache \(kind): \(counts.hits) hits, \(counts.misses) misses, "
                + "\(counts.stale + counts.unreadable) stale")
        }
        if let stats = fastLoader?.control.snapshot {
            print("[INFO] fast load: \(stats.batches) batches, \(stats.textures) textures, "
                + "\(stats.bytes >> 20) MiB, \(stats.meshes) meshes, "
                + "\(stats.meshBytes >> 20) MiB, \(stats.fallbacks) fallbacks")
        }
        guard let recordPath else { return }
        try (cache.requestedPaths.sorted().joined(separator: "\n") + "\n")
            .write(toFile: recordPath, atomically: true, encoding: .utf8)
        print("[INFO] wrote \(cache.requestedPaths.count) asset paths -> \(recordPath)")
    }
}
