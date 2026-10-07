// `asset-cache build|check|clear|status|extract|io-bench|measure|compare`: builds the asset cache
// without
// the app, with the preset and folder from the shared settings unless options override them. The
// cache is game content and lives outside the repo (AGENTS.md Legal & IP); the location check
// refuses a folder inside a git checkout or the install.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld

enum AssetCacheCommand {
    private struct Options {
        var settings: AssetCacheSettings
        var kinds: Set<AssetCacheKind>
        var width: Int?
        /// Only these paths, one per line in the `--paths` file, instead of the whole install.
        var paths: [String]?
        var out: URL?
        var perKind: Int
    }

    static func run(context: CLIContext, scanner: inout ArgumentScanner) async throws {
        let subcommand = try scanner
            .positional("build|check|clear|status|extract|io-bench|measure|compare")
        if subcommand == "compare" {
            return try compare(scanner: &scanner)
        }
        let options = try Options(
            settings: settings(scanner: &scanner),
            kinds: kinds(scanner.option("--kinds")),
            width: scanner.option("--width").map { try int($0, "--width") },
            paths: scanner.option("--paths").map { try lines(ofFile: $0) },
            out: scanner.option("--out").map { URL(filePath: $0, directoryHint: .isDirectory) },
            perKind: scanner.option("--per-kind").map { try int($0, "--per-kind") } ?? 300
        )
        try scanner.finish()
        let files = context.makeFileSystem()
        let reader = try AssetCacheReader.open(
            settings: options.settings, files: files, gameInstall: context.root.installURL
        )
        switch subcommand {
        case "build":
            try await build(reader: reader, files: files, options: options)
        case "check":
            try await check(reader: reader, files: files, options: options)
        case "clear":
            try reader.store.clear()
            print("cleared \(reader.store.root.path(percentEncoded: false))")
        case "status":
            status(reader: reader, settings: options.settings)
        case "extract":
            try extract(files: files, options: options, install: context.root.installURL)
        case "io-bench":
            try ioBench(
                reader: reader,
                files: files,
                options: options,
                dataURL: context.root.dataURL
            )
        case "measure":
            try await AssetCacheMeasure.run(
                reader: reader, files: files, settings: options.settings,
                dataURL: context.root.dataURL, perKind: options.perKind
            )
        default:
            throw CLIError.usage("unknown asset-cache subcommand: \(subcommand)")
        }
    }

    private static func lines(ofFile path: String) throws -> [String] {
        try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    /// Writes loose copies of `--paths` into `--out`, the baseline the cache formats compare with.
    private static func extract(files: VirtualFileSystem, options: Options, install: URL) throws {
        guard let out = options.out, let paths = options.paths else {
            throw CLIError.usage("extract needs --paths <file> and --out <folder>")
        }
        try AssetCacheLocation.validate(out, gameInstall: install)
        let loose = FolderOverlayFileSource(base: files, folder: out)
        var bytes = 0
        for path in paths {
            let url = try loose.looseURL(forPath: path)
            let data = try files.contents(forPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            bytes += data.count
        }
        let folder = out.path(percentEncoded: false)
        print("extracted \(paths.count) files, \(bytes >> 20) MiB -> \(folder)")
    }

    /// Compares two captures of the same view, such as the benchmark frame with the cache off and
    /// on.
    private static func compare(scanner: inout ArgumentScanner) throws {
        let reference = try scanner.positional("reference.png")
        let candidate = try scanner.positional("candidate.png")
        try scanner.finish()
        let difference = try TextureImageDifference.compare(
            reference: TexturePixels(contentsOf: URL(filePath: reference)),
            candidate: TexturePixels(contentsOf: URL(filePath: candidate)), normals: false
        )
        print(String(
            format: "rgb PSNR %.2f dB, max channel error %d",
            difference.rgbPSNR,
            difference.maxChannelError
        ))
    }

    /// Loads the `--paths` textures as one batch each way, cold and then warm.
    private static func ioBench(
        reader: AssetCacheReader, files: VirtualFileSystem, options: Options, dataURL: URL
    ) throws {
        guard let paths = options.paths
        else { throw CLIError.usage("io-bench needs --paths <file>") }
        guard let device = MTLCreateSystemDefaultDevice()
        else { throw CLIError.failure("no Metal GPU") }
        let bench = try TextureBatchLoadBenchmark(
            device: device,
            files: files,
            reader: reader,
            paths: paths
        )
        guard bench.textureCount > 0
        else { throw CLIError.failure("no listed texture has a cache entry") }
        let copies = reader.store.root.appending(path: "io-bench-lz4", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: copies) }
        try bench.prepareCompressedCopies(in: copies)
        let lz4Bytes = bench.compressedURLs
            .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
        print("[INFO] \(bench.textureCount) textures; LZ4 copies \(lz4Bytes >> 20) MiB")
        print("method\tpass\ttextures\tMiB\twall ms\tcpu ms")
        for method in TextureBatchLoadMethod.allCases {
            for pass in ["cold", "warm"] {
                if pass == "cold" {
                    PageCacheEviction.evict(folders: [dataURL, copies])
                    for url in bench.entryURLs {
                        PageCacheEviction.evict(file: url)
                    }
                }
                let timing = try bench.run(method)
                print(String(
                    format: "%@\t%@\t%d\t%d\t%.1f\t%.1f", method.rawValue, pass, timing.textures,
                    timing.bytes >> 20, timing.wallMS, timing.cpuMS
                ))
            }
        }
    }

    /// The shared settings, with `--preset`, `--folder`, and `--limit-gib` on top.
    @MainActor
    static func settings(scanner: inout ArgumentScanner) throws -> AssetCacheSettings {
        var settings =
            AssetCacheSettings(store: PlayerSettingsStore(persistence: try? PlayerSettingsFile
                    .defaultFile()))
        if let name = try scanner.option("--preset") {
            guard let preset = AssetQualityPreset.allCases.first(where: { $0.cliName == name })
            else {
                throw CLIError.usage("--preset is best, balanced, or highest")
            }
            settings.preset = preset
        }
        if let folder = try scanner.option("--folder") {
            settings.folder = URL(filePath: folder, directoryHint: .isDirectory)
        }
        if let limit = try scanner.option("--limit-gib") {
            settings.limitBytes = try UInt64(int(limit, "--limit-gib")) << 30
        }
        return settings
    }

    private static func kinds(_ list: String?) throws -> Set<AssetCacheKind> {
        guard let list else { return [] }
        return try Set(list.split(separator: ",").map { name in
            let built = AssetCacheKind.allCases.filter { !AssetCacheKind.retired.contains($0) }
            guard let kind = built.first(where: { $0.folderName == name }) else {
                let names = built.map(\.folderName).joined(separator: ",")
                throw CLIError.usage("--kinds takes \(names)")
            }
            return kind
        })
    }

    private static func int(_ text: String, _ option: String) throws -> Int {
        guard
            let value = Int(text),
            value > 0 else { throw CLIError.usage("\(option) needs a positive number") }
        return value
    }

    private static func builder(
        reader: AssetCacheReader, files: VirtualFileSystem, options: Options
    ) throws -> AssetCacheBuilder {
        let converters = try AssetCacheConverters.make(preset: options.settings.preset)
        return AssetCacheBuilder(
            store: reader.store, files: files,
            converters: AssetCacheConverters.filter(converters, kinds: options.kinds),
            preset: options.settings.preset
        )
    }

    private static func items(
        _ builder: AssetCacheBuilder,
        options: Options
    ) -> [AssetCacheBuildItem] {
        options.paths.map { builder.plan(paths: $0) } ?? builder.planInstall()
    }

    private static func build(
        reader: AssetCacheReader,
        files: VirtualFileSystem,
        options: Options
    ) async throws {
        let settings = options.settings
        let builder = try builder(reader: reader, files: files, options: options)
        let items = items(builder, options: options)
        let total = items.reduce(UInt64(0)) { $0 + (files.provenance(forPath: $1.path)?.size ?? 0) }
        for warning in reader.store
            .locationWarnings(neededBytes: settings.preset.estimatedBaseGameCacheBytes)
        {
            printError("[WARNING] \(warning.message)")
        }
        let preset = settings.preset.title
        printError("[INFO] \(items.count) items, \(total >> 20) MiB of sources, preset \(preset)")
        let throttle = AssetCacheProgressThrottle(interval: .seconds(5))
        let result = await Task(priority: .utility) {
            await builder.build(
                items,
                width: options.width ?? ProcessInfo.processInfo.activeProcessorCount
            ) { progress in
                if throttle.shouldReport(progress) {
                    printError("[INFO] \(progress.summaryLine)")
                }
            }
        }.value
        for failure in result.failures.prefix(20) {
            printError("[WARNING] \(failure.kind) \(failure.path): \(failure.reason)")
        }
        print(result.summaryLine)
        print("failures \(result.failures.count)")
    }

    private static func check(
        reader: AssetCacheReader,
        files: VirtualFileSystem,
        options: Options
    ) async throws {
        let builder = try builder(reader: reader, files: files, options: options)
        let check = await builder.check(items(builder, options: options))
        for kind in AssetCacheKind.allCases {
            let counts = check.kinds[kind] ?? AssetCacheKindCheck()
            let line = "current \(counts.current)\tstale \(counts.stale)\tmissing \(counts.missing)"
            print("\(kind)\t\(line)")
        }
    }

    private static func status(reader: AssetCacheReader, settings: AssetCacheSettings) {
        let usage = reader.store.usage()
        print("folder\t\(reader.store.root.path(percentEncoded: false))")
        print("preset\t\(settings.preset.title)")
        print("entries\t\(usage.entryCount)")
        print("size\t\(usage.bytes >> 20) MiB of \(reader.store.limitBytes >> 30) GiB")
        for warning in reader.store.locationWarnings(neededBytes: 0) {
            print("warning\t\(warning.message)")
        }
    }
}

extension AssetQualityPreset {
    var cliName: String {
        switch self {
        case .bestPerformance: "best"
        case .balanced: "balanced"
        case .highestQuality: "highest"
        }
    }
}
