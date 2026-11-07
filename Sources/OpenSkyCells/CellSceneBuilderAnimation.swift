// Builds a resident actor's idle playback from its assembly, caching one clip per
// skeleton and sex on the builder.

public import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
public import OpenSkyRendering

nonisolated extension CellSceneBuilder {
    /// `severedHead` marks the cut head of a decapitated actor, posed apart from its body.
    nonisolated public func makeAnimationPlayback(
        assembly: ActorAssembly<ActorRenderAsset>,
        severedHead: Bool = false
    ) -> Result<ActorAnimationPlayback, ActorAnimationLoadError> {
        guard let skeletonPath = assembly.visual.skeletonPath else {
            return .failure(.unsupportedSkeleton("<missing>"))
        }
        guard let meshPath = attempt({ try VirtualFileSystem.meshPath(skeletonPath) }) else {
            return .failure(.unsupportedSkeleton(skeletonPath))
        }
        let key = ActorAnimationCacheKey(
            skeletonPath: meshPath,
            female: assembly.visual.appearance.isFemale.value
        )
        let clip: ActorAnimationClip
        if let cached = actorAnimationClips[key] {
            clip = cached
        } else {
            do {
                clip = try loadAnimationClip(key: key)
                actorAnimationClips[key] = clip
            } catch let error as ActorAnimationLoadError {
                return .failure(error)
            } catch {
                return .failure(.invalid(key.skeletonPath, error))
            }
        }
        return .success(ActorAnimationPlayback(
            actor: assembly.actor,
            clip: clip,
            models: assembly.models.map(\.asset.model),
            female: assembly.visual.appearance.isFemale.value,
            transform: assembly.transform,
            sheathNodes: assembly.visual.sheathNodes,
            armorAddons: assembly.visual.wornArmorAddons,
            posesSeveredHead: severedHead,
            lagBones: lagBoneRig(skeletonMeshPath: meshPath, clip: clip)
        ))
    }

    /// The lag bones of a skeleton mesh, read once per skeleton.
    nonisolated func lagBoneRig(
        skeletonMeshPath path: String, clip: ActorAnimationClip
    ) -> ActorLagBoneRig? {
        if let known = actorLagBoneRigs[path] {
            return known
        }
        let file = fileSystem
            .flatMap { element in attempt { try NIFFile(data: element.contents(forPath: path)) } }
        let rig = file.flatMap {
            ActorLagBoneRig(file: $0, rigBones: Set(clip.skeleton.boneNames))
        }
        actorLagBoneRigs[path] = .some(rig)
        return rig
    }

    nonisolated private func loadAnimationClip(
        key: ActorAnimationCacheKey
    ) throws -> ActorAnimationClip {
        try ActorAnimationClipLoader.clip(
            skeletonMeshPath: key.skeletonPath,
            animationPaths: ActorAnimationClipLoader.idleAnimationPaths(
                skeletonMeshPath: key.skeletonPath, female: key.female
            ),
            exists: { fileSystem?.exists($0) ?? false },
            readHKX: readHKX
        )
    }

    nonisolated private func readHKX(path: String) throws -> HKXFile {
        guard let fileSystem, let data = attempt({ try fileSystem.contents(forPath: path) }) else {
            throw ActorAnimationLoadError.missing(path)
        }
        do {
            return try HKXFile(data: data)
        } catch {
            throw ActorAnimationLoadError.invalid(path, error)
        }
    }
}
