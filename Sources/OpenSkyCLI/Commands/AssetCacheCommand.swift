// `asset-optimisation build|check|clear|status|extract|io-bench|measure|compare`: converts
// without the app, with the texture quality and folder from the shared settings unless options
// override them. The files are game content and live outside the repo (AGENTS.md Legal & IP);
// the location check refuses a folder inside a git checkout or the install.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyCLIArguments
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld

enum AssetCacheCommand {
    private struct Options {
        var settings: AssetCacheSettings
        var width: Int?
        /// Only these paths, one per line in the `--paths` file, instead of the whole install.
        var paths: [String]?
        var out: URL?
        var perKind: Int
    }

    static func run(
        context: CLIContext,
        action: AssetCacheAction,
        arguments: AssetCacheActionOptions
    ) async throws {
        let options = try Options(
            settings: settings(arguments.settings),
            width: arguments.width.map { try int($0, "--width") },
            paths: arguments.paths.map { try lines(ofFile: $0) },
            out: arguments.out.map { URL(filePath: $0, directoryHint: .isDirectory) },
            perKind: arguments.perKind.map { try int($0, "--per-kind") } ?? 300
        )
        let files = context.makeFileSystem()
        let reader = try AssetCacheReader.open(
            settings: options.settings, files: files, gameInstall: context.root.installURL
        )
        switch action {
        case .build:
            try await build(reader: reader, files: files, options: options)
        case .check:
            try await check(reader: reader, files: files, options: options)
        case .clear:
            try reader.store.clear()
            print("cleared \(reader.store.root.path(percentEncoded: false))")
        case .status:
            status(reader: reader, settings: options.settings)
        case .extract:
            try extract(files: files, options: options, install: context.root.installURL)
        case .ioBench:
            try ioBench(
                reader: reader,
                files: files,
                options: options,
                dataURL: context.root.dataURL
            )
        case .measure:
            try await AssetCacheMeasure.run(
                reader: reader, files: files, settings: options.settings,
                dataURL: context.root.dataURL, perKind: options.perKind
            )
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
    static func compare(arguments: AssetCacheArguments.Compare) throws {
        let reference = arguments.reference
        let candidate = arguments.candidate
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
                    format: "%@\t%@\t%d\t%d\t%.1f\t%.1f", timing.method.rawValue, pass,
                    timing.textures,
                    timing.bytes >> 20, timing.wallMS, timing.cpuMS
                ))
            }
        }
    }

    /// The shared settings, with `--texture-quality`, `--max-texture-side`, `--folder`, and
    /// `--kinds` on top.
    @MainActor
    static func settings(_ arguments: AssetCacheSettingsOptions) throws -> AssetCacheSettings {
        var settings =
            AssetCacheSettings(store: PlayerSettingsStore(persistence: try? PlayerSettingsFile
                    .defaultFile()))
        if let name = arguments.textureQuality {
            guard let quality = TextureQuality.allCases.first(where: { $0.cliName == name }) else {
                throw CLIError.usage("--texture-quality is original, high, medium, or low")
            }
            settings.textureOutput.quality = quality
        }
        if let side = arguments.maxTextureSide {
            settings.textureOutput.maximumSide = try int(side, "--max-texture-side")
        }
        if let folder = arguments.folder {
            settings.folder = URL(filePath: folder, directoryHint: .isDirectory)
        }
        if let list = arguments.kinds {
            settings.kinds = try kinds(list)
        }
        return settings
    }

    private static func kinds(_ list: String) throws -> Set<AssetCacheKind> {
        try Set(list.split(separator: ",").map { name in
            guard
                let kind = AssetCacheKind(folderName: String(name)),
                AssetCacheKind.built.contains(kind)
            else {
                let names = AssetCacheKind.built.map(\.folderName).joined(separator: ",")
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
        let converters = try AssetCacheConverters
            .make(textureOutput: options.settings.textureOutput)
        return AssetCacheBuilder(
            store: reader.store, files: files,
            converters: converters.filter { options.settings.kinds.contains($0.kind) },
            textureOutput: options.settings.textureOutput
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
        let space = await AssetSpaceCheck(
            check: builder.check(items), output: settings.textureOutput,
            volume: AssetCacheVolume.of(reader.store.root)
        )
        printError("[INFO] \(space.line)")
        for warning in space.warnings {
            printError("[WARNING] \(warning.message)")
        }
        let quality = settings.textureOutput.quality.title
        printError(
            "[INFO] \(items.count) items, \(total >> 20) MiB of sources, texture quality \(quality)"
        )
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
        for kind in AssetCacheKind.built {
            let counts = check.kinds[kind] ?? AssetCacheKindCheck()
            let line = "current \(counts.current)\tstale \(counts.stale)\tmissing \(counts.missing)"
            print("\(kind)\t\(line)")
        }
    }

    private static func status(reader: AssetCacheReader, settings: AssetCacheSettings) {
        let usage = reader.store.usage()
        print("folder\t\(reader.store.root.path(percentEncoded: false))")
        print("texture quality\t\(settings.textureOutput.quality.title)")
        print("entries\t\(usage.entryCount)")
        print("size\t\(usage.bytes >> 20) MiB")
        for kind in AssetCacheKind.built {
            let kindUsage = usage.kinds[kind] ?? AssetCacheKindUsage()
            let stored = settings.kinds.contains(kind) ? "cached" : "archives"
            print(
                "\(kind)\t\(stored), \(kindUsage.entryCount) entries, \(kindUsage.bytes >> 20) MiB"
            )
        }
        for warning in reader.store.locationWarnings(neededBytes: 0) {
            print("warning\t\(warning.message)")
        }
    }
}

extension TextureQuality {
    var cliName: String {
        title.lowercased()
    }
}
