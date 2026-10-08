// `launch-bench`: times each stage of the world data load the app runs before
// its game window opens, against the install. Same loader, same parallel stages.

import Foundation
import Metal
import OpenSkyGameData
import OpenSkyWorld
import Synchronization

enum LaunchBenchCommand {
    static func run(context: CLIContext) async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw CLIError.failure("no Metal device")
        }
        let events = Mutex<[WorldLoadEvent]>([])
        let progress = WorldLoadProgress { event in events.withLock { $0.append(event) } }
        let start = ContinuousClock.now
        let fileSystem = try progress.measure(.archives) { context.makeFileSystem() }
        _ = try await CellProviderIndexes.loadSession(
            root: context.root,
            fileSystem: fileSystem,
            device: device,
            localizationLanguage: LocalizationLanguageSettings.load(root: context.root).language,
            terrainLODConfigurationStore: context.makeTerrainLODConfigurationStore(),
            progress: progress
        )
        let total = ContinuousClock.now - start
        var timeline = WorldLoadTimeline()
        for event in events.withLock(\.self) {
            timeline.apply(event)
        }
        let stages = timeline.slowestFirst
        for (stage, duration) in stages {
            print("stage \(stage.rawValue) \(duration.secondsText)")
        }
        let summed = stages.reduce(Duration.zero) { $0 + $1.duration }
        // Stages overlap, so the wall time is less than their sum.
        print("total \(total.secondsText) wall, \(summed.secondsText) summed, "
            + "\(stages.count) stages")
    }
}
