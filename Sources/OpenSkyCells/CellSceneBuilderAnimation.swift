// Builds a resident actor's idle playback from its assembly, caching one clip per
// skeleton and sex on the builder.

import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyGameData
import OpenSkyRendering

nonisolated extension CellSceneBuilder {
    nonisolated public func makeAnimationPlayback(
        assembly: ActorAssembly<ActorRenderAsset>
    ) -> Result<ActorAnimationPlayback, ActorAnimationLoadError> {
        guard let skeletonPath = assembly.visual.skeletonPath else {
            return .failure(.unsupportedSkeleton("<missing>"))
        }
        let normalizedPath: String
        do {
            normalizedPath = try VirtualFileSystem.normalize(skeletonPath)
        } catch {
            return .failure(.unsupportedSkeleton(skeletonPath))
        }
        let meshPath = normalizedPath.hasPrefix("meshes\\")
            ? normalizedPath : "meshes\\" + normalizedPath
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
            sheathNodes: assembly.visual.sheathNodes
        ))
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
        guard let fileSystem, let data = try? fileSystem.contents(forPath: path) else {
            throw ActorAnimationLoadError.missing(path)
        }
        do {
            return try HKXFile(data: data)
        } catch {
            throw ActorAnimationLoadError.invalid(path, error)
        }
    }
}
