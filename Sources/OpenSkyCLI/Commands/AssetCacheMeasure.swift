// `asset-cache measure`: per asset kind, the time to load a fixed sample from
// the original archive files against the time to load it from the cache, cold
// and warm. The answer says which kinds are worth caching on this Mac
// (docs/engine/asset-cache.md, "Where the cache helps").

import Darwin
import Foundation
import OpenSkyAssetCache
import OpenSkyAudio
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyWorld

enum AssetCacheMeasure {
    /// One kind's two load paths. Each returns nothing: only the time counts.
    private struct Probe {
        let kind: AssetCacheKind
        let original: (Data) throws -> Void
        let cached: (AssetCacheReader, String) -> Bool
    }

    private struct Context {
        let files: VirtualFileSystem
        let reader: AssetCacheReader
        /// Dropped from the page cache before each cold pass.
        let evict: [URL]
    }

    private struct Row {
        let pass: String
        let archive: Timing
        let cache: Timing
    }

    private struct Timing {
        var wallMS = 0.0
        var cpuMS = 0.0
        var bytes = 0
    }

    private static let probes: [Probe] = [
        Probe(
            kind: .texture,
            original: { _ = try ReadyTexture.shipped(dds: $0) },
            cached: { $0.value(forPath: $1, decoder: .readyTexture) != nil }
        ),
        Probe(
            kind: .mesh,
            original: { _ = try NIFFile(data: $0).model(skeleton: nil) },
            cached: { $0.value(forPath: $1, decoder: .model) != nil }
        ),
        Probe(
            kind: .collision,
            original: { _ = try NIFFile(data: $0).collisionModel() },
            cached: { $0.value(forPath: $1, decoder: .collision) != nil }
        ),
        Probe(
            kind: .animation,
            original: { _ = $0.count },
            cached: { $0.value(forPath: $1, decoder: .looseAnimation) != nil }
        ),
        Probe(
            kind: .audio,
            original: { _ = try CachedAudioConverter.decode($0) },
            cached: { $0.value(forPath: $1, decoder: .cachedAudio) != nil }
        )
    ]

    static func run(
        reader: AssetCacheReader,
        files: VirtualFileSystem,
        settings: AssetCacheSettings,
        dataURL: URL,
        perKind: Int
    ) async throws {
        // Kinds the cache no longer stores are measured too, so the decision can be checked again.
        let built = try AssetCacheConverters.make(textureOutput: settings.textureOutput)
        let retired: [any AssetConverting] = [LooseAnimationConverter(), CachedAudioConverter()]
        let converters = built + retired.filter { old in !built.contains { $0.kind == old.kind } }
        reader.kinds = Set(AssetCacheKind.allCases)
        let context = Context(files: files, reader: reader, evict: [dataURL, reader.store.root])
        let builder = AssetCacheBuilder(
            store: reader.store, files: files, converters: converters,
            textureOutput: settings.textureOutput
        )
        let paths = files.archiveEntries().map(\.path).sorted()
        print(
            "kind\tfiles\tsource MiB\tcache MiB\tpass\tarchive ms\tcache ms\tarchive cpu\tcache cpu"
        )
        for probe in probes {
            guard let converter = converters.first(where: { $0.kind == probe.kind })
            else { continue }
            let sample = evenSample(paths.filter(converter.accepts), count: perKind)
            _ = await builder
                .build(builder.plan(paths: sample).filter { $0.converter.kind == probe.kind })
            let stored = sample.filter { probe.cached(reader, $0) }
            let cacheBytes = stored.reduce(0) { total, path in
                guard let stamp = reader.stamp(forPath: path) else { return total }
                let url = reader.store.entryURL(kind: probe.kind, source: stamp)
                return total + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            try measure(probe, paths: stored, context: context, cacheBytes: cacheBytes)
        }
    }

    private static func measure(
        _ probe: Probe, paths: [String], context: Context, cacheBytes: Int
    ) throws {
        var rows: [Row] = []
        var archive: [String: Timing] = [:]
        for pass in ["cold", "warm"] {
            if pass == "cold" {
                PageCacheEviction.evict(folders: context.evict)
            }
            archive[pass] = try time(paths) { path in
                let bytes = try context.files.contents(forPath: path)
                try probe.original(bytes)
                return bytes.count
            }
        }
        for pass in ["cold", "warm"] {
            if pass == "cold" {
                PageCacheEviction.evict(folders: context.evict)
            }
            let cache = try time(paths) { path in
                guard probe.cached(context.reader, path) else {
                    throw CLIError.failure("\(probe.kind) \(path) lost its cache entry")
                }
                return 0
            }
            rows.append(Row(pass: pass, archive: archive[pass] ?? Timing(), cache: cache))
        }
        let sourceMiB = Double(rows.first?.archive.bytes ?? 0) / Double(1 << 20)
        for row in rows {
            print(String(
                format: "%@\t%d\t%.1f\t%.1f\t%@\t%.1f\t%.1f\t%.1f\t%.1f",
                probe.kind.description, paths.count, sourceMiB,
                Double(cacheBytes) / Double(1 << 20),
                row.pass, row.archive.wallMS, row.cache.wallMS, row.archive.cpuMS, row.cache.cpuMS
            ))
        }
        print("advice\t\(probe.kind)\t\(advice(probe.kind, rows: rows))")
    }

    /// The rule of docs/engine/asset-cache.md: at least half the warm time and no
    /// slower cold, or a Metal 4 loading path.
    private static func advice(_ kind: AssetCacheKind, rows: [Row]) -> String {
        let hasMetalPath = kind == .texture || kind == .mesh
        let faster = rows.allSatisfy { row in
            row.pass == "warm"
                ? row.cache.wallMS * 2 <= row.archive.wallMS
                : row.cache.wallMS <= row.archive.wallMS
        }
        return faster || hasMetalPath ? "cache" : "archives"
    }

    private static func time(_ paths: [String], _ load: (String) throws -> Int) throws -> Timing {
        let wallStart = DispatchTime.now().uptimeNanoseconds
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        var bytes = 0
        for path in paths {
            bytes += try load(path)
        }
        return Timing(
            wallMS: Double(DispatchTime.now().uptimeNanoseconds - wallStart) / 1e6,
            cpuMS: Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1e6,
            bytes: bytes
        )
    }

    /// `count` paths spread evenly over the sorted list, so every folder is represented.
    private static func evenSample(_ paths: [String], count: Int) -> [String] {
        guard paths.count > count else { return paths }
        let step = Double(paths.count) / Double(count)
        return (0 ..< count).map { paths[Int(Double($0) * step)] }
    }
}
