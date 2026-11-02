// `load-pass`: runs the benchmark's cold and warm cell builds of one scene off the app,
// so a decode change can be timed against the disk alone (docs/tools/benchmark.md).

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyCLIArguments
import OpenSkyGameData
import OpenSkyWorld

enum LoadPassCommand {
    static func run(context: CLIContext, arguments: LoadPassArguments) async throws {
        guard let scene = BenchmarkTour.scene(id: arguments.scene) else {
            throw CLIError.usage("no benchmark scene \(arguments.scene); see 'benchmark --list'")
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CLIError.failure("no Metal device")
        }
        let cache = try arguments.assetCache ? openCache(context: context) : nil
        let inputs = BenchmarkLoadInputs(
            root: context.root, device: device,
            terrainLOD: ColdCellBuilder.terrainLODStore(
                root: context.root, settings: PlayerSettingsFile.savedData()
            ),
            decodesInParallel: !arguments.serial, assetCache: cache
        )
        let decode = arguments.serial ? "serial" : "parallel"
        print("[INFO] \(scene.place.label), \(decode) decode, "
            + (cache == nil ? "archives only" : "asset cache"))
        print("run\tpass\ttotal ms\t" + LoadPhase.allCases.map { "\($0.rawValue) ms" }
            .joined(separator: "\t") + "\tother ms")
        for run in 1 ... arguments.runs {
            if arguments.evict {
                let evicted = PageCacheEviction.evict(
                    folders: BenchmarkCommand.evictFolders(context: context)
                )
                print("[INFO] evicted \(evicted >> 20) MiB from the page cache")
            }
            let passes = try await BenchmarkLoadPasses.run(place: scene.place, inputs: inputs)
            print(row(run: run, pass: "cold", passes.cold))
            print(row(run: run, pass: "warm", passes.warm))
        }
    }

    private static func openCache(context: CLIContext) throws -> AssetCacheReader {
        let settings = AssetCacheSettings(
            store: PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
        )
        return try AssetCacheReader.open(
            settings: settings, files: context.makeFileSystem(),
            gameInstall: context.root.installURL
        )
    }

    private static func row(run: Int, pass: String, _ result: BenchmarkLoadPass) -> String {
        let phases = LoadPhase.allCases.map { String(format: "%.0f", result.phases[$0]) }
        return "\(run)\t\(pass)\t" + String(format: "%.0f", result.totalMS) + "\t"
            + phases.joined(separator: "\t") + "\t"
            + String(format: "%.0f", result.phases.otherMS)
    }
}
