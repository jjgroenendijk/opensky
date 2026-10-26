// The behaviour project an effect art model names, decoded off the main actor and
// shared by every effect that draws the model. See docs/engine/effect-graphs.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsMesh
import OpenSkyGameData

/// A model's project decoded off the main actor, with its behaviour folder indexed.
nonisolated struct LoadedEffectGraphProject: Sendable {
    let asset: BehaviorProjectAsset
    let referencePaths: [String: String]

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
            return Self(asset: asset, referencePaths: references)
        }
    }
}

/// One project's shared decode, clips, and behaviour references.
@MainActor
final class EffectGraphProject {
    let asset: BehaviorProjectAsset
    let clips: InstallBehaviorClipSource
    let references: InstallBehaviorReferenceSource
    let skeleton: BehaviorSkeleton
    let objects: SharedBehaviorObjectSource
    /// Every effect of the model reaches the same clips, so the first one asks for them.
    private var hasPrefetched = false

    init(_ loaded: LoadedEffectGraphProject, files: any GameFileSource) {
        asset = loaded.asset
        objects = SharedBehaviorObjectSource(graph: loaded.asset.objectGraph)
        let worker = SerialAssetLoadWorker<String, SplineBehaviorClip>(
            queue: AssetLoadQueue.background,
            load: InstallBehaviorClipSource.load(fileSystem: files)
        )
        clips = InstallBehaviorClipSource(paths: loaded.asset.clipPaths, worker: worker)
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
        instance.activate()
        if !hasPrefetched {
            hasPrefetched = true
            instance.prefetchReachableClips()
        }
        return instance
    }
}
