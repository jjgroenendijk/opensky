// The behaviour project an effect art model names, decoded off the main actor and
// shared by every effect that draws the model. See docs/engine/effect-graphs.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData

/// A model's project decoded off the main actor, with its behaviour folder indexed.
nonisolated struct LoadedEffectGraphProject: Sendable {
    let asset: BehaviorProjectAsset
    let referencePaths: [String: String]
    let sequenceTimings: [String: GamebryoSequenceTiming]

    /// Nil when the model names no behaviour project, the common case.
    static func load(
        _ files: any GameFileSource
    ) -> @Sendable (String) throws -> Self? {
        { modelPath in
            let key = modelPath.lowercased().replacingOccurrences(of: "/", with: "\\")
            let meshPath = key.hasPrefix("meshes\\") ? key : "meshes\\" + key
            let file = try NIFFile(data: files.contents(forPath: meshPath))
            guard let projectPath = NIFBehaviorGraphExtraData.projectPath(in: file) else {
                return nil
            }
            let asset = try BehaviorProjectAsset.load(
                fileSystem: files, projectPath: projectPath, folderClips: true
            )
            let references = InstallBehaviorReferenceSource.index(
                files, rootPath: asset.behaviorPath
            )
            let timings = attempt { try file.sequences() } ?? []
            return Self(
                asset: asset, referencePaths: references,
                sequenceTimings: GamebryoSequenceTiming.byName(timings)
            )
        }
    }
}

nonisolated extension GamebryoSequenceTiming {
    /// The timing of each sequence of a mesh, its text keys in seconds from its start.
    static func byName(_ sequences: [NIFSequence]) -> [String: GamebryoSequenceTiming] {
        var timings: [String: GamebryoSequenceTiming] = [:]
        for sequence in sequences {
            let timing = sequence.timing
            let rate = max(timing.frequency, .ulpOfOne)
            let keys = sequence.textKeys.map {
                Key(time: ($0.time - timing.startTime) / rate, name: $0.value)
            }
            timings[sequence.name] = GamebryoSequenceTiming(
                duration: sequence.duration, loops: timing.cycle != .clamp, keys: keys
            )
        }
        return timings
    }
}

/// One project's shared decode, clips, and behaviour references.
@MainActor
final class EffectGraphProject {
    let asset: BehaviorProjectAsset
    let sequenceTimings: [String: GamebryoSequenceTiming]
    let clips: InstallBehaviorClipSource
    let references: InstallBehaviorReferenceSource
    let skeleton: BehaviorSkeleton
    let objects: SharedBehaviorObjectSource
    /// Every effect of the model reaches the same clips, so the first one asks for them.
    private var hasPrefetched = false

    init(_ loaded: LoadedEffectGraphProject, files: any GameFileSource) {
        asset = loaded.asset
        sequenceTimings = loaded.sequenceTimings
        objects = SharedBehaviorObjectSource(graph: loaded.asset.objectGraph)
        let worker = SerialAssetLoadWorker<String, SplineBehaviorClip>(
            queue: AssetLoadQueue.background,
            load: InstallBehaviorClipSource.load(fileSystem: files)
        )
        clips = InstallBehaviorClipSource(project: loaded.asset, worker: worker)
        references = InstallBehaviorReferenceSource(
            fileSystem: files, pathsByName: loaded.referencePaths
        )
        // An effect never walks, so no bone is a root whose travel leaves the pose.
        skeleton = BehaviorSkeleton(loaded.asset.skeleton, rootBoneIndex: -1)
    }

    func instance() -> BehaviorGraphInstance {
        let instance = BehaviorGraphInstance(
            graph: asset.behavior, in: asset.objectGraph,
            skeleton: skeleton, clips: clips, objects: objects
        )
        instance.references = references
        instance.characterProperties = asset.characterProperties
        instance.sequenceClock = GamebryoSequenceClock(timings: sequenceTimings)
        instance.activate()
        if !hasPrefetched {
            hasPrefetched = true
            instance.prefetchReachableClips()
        }
        return instance
    }
}
