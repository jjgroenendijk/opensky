// The asset cache and loose file options the benchmarks share: `--asset-cache`,
// `--evict`, `--loose <dir>`, `--record-paths <file>`, and the cache settings
// options of `asset-cache`.

import Foundation
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld

struct AssetLoadOptions {
    let cache: AssetCacheReader?
    let looseFolder: URL?
    let recordPath: String?

    init(scanner: inout ArgumentScanner, context: CLIContext) throws {
        let useCache = scanner.flag("--asset-cache")
        let evict = scanner.flag("--evict")
        let loose = try scanner.option("--loose")
        looseFolder = loose.map { URL(filePath: $0, directoryHint: .isDirectory) }
        recordPath = try scanner.option("--record-paths")
        let settings = try AssetCacheCommand.settings(scanner: &scanner)
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

    /// Points the builder's libraries at the cache.
    func configure(_ builder: CellSceneBuilder) {
        builder.textures.assetCache = cache
        builder.meshes.assetCache = cache
        builder.collisionModels?.assetCache = cache
    }

    func report() throws {
        guard let cache else { return }
        for kind in [AssetCacheKind.texture, .mesh] {
            let counts = cache.counts(for: kind)
            print("[INFO] asset cache \(kind): \(counts.hits) hits, \(counts.misses) misses, "
                + "\(counts.stale + counts.unreadable) stale")
        }
        guard let recordPath else { return }
        try (cache.requestedPaths.sorted().joined(separator: "\n") + "\n")
            .write(toFile: recordPath, atomically: true, encoding: .utf8)
        print("[INFO] wrote \(cache.requestedPaths.count) asset paths -> \(recordPath)")
    }
}
