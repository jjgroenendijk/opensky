// Actor-facing model loading, split from MeshLibrary.swift for the strict-lint
// type-body length cap. Same cache, same build-queue confinement, same failure
// policy — this file only holds the three entry points actor assembly uses and
// the shared character-skeleton lookup behind them.

import Foundation
import Metal
import simd

nonisolated extension MeshLibrary {
    func loadActorSkeleton(path: String) -> Result<ActorSkeletonAsset, ActorAssetFailure> {
        let pathKey: String
        do {
            pathKey = try meshKey(for: path)
        } catch {
            return .failure(.missing)
        }
        if let skeleton = actorSkeletons[pathKey] {
            return .success(ActorSkeletonAsset(pathKey: pathKey, skeleton: skeleton))
        }
        guard let data = try? fileSystem.contents(forPath: pathKey) else {
            return .failure(.missing)
        }
        do {
            let skeleton = try NIFSkeleton(file: NIFFile(data: data))
            actorSkeletons[pathKey] = skeleton
            return .success(ActorSkeletonAsset(pathKey: pathKey, skeleton: skeleton))
        } catch {
            return .failure(.invalid)
        }
    }

    func loadActorModel(
        path: String,
        skeleton: ActorSkeletonAsset?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        do {
            let model = try loadModel(
                path: path,
                terrainLODClipMask: nil,
                actorSkeleton: skeleton,
                explicitActorSkeleton: true
            )
            let pathKey = try meshKey(for: path)
            let key = cacheKey(
                path: pathKey,
                terrainLODClipMask: nil,
                actorSkeletonKey: skeleton?.pathKey ?? "none"
            )
            return .success(ActorRenderAsset(model: model, bounds: modelBounds[key]))
        } catch MeshLibraryError.fileNotFound {
            return .failure(.missing)
        } catch {
            return .failure(.invalid)
        }
    }

    /// A rigid model rewritten to ride `bone`, cached separately from the same
    /// path loaded as ordinary static geometry: the same sword is a different
    /// mesh in a hand than it is lying on a table (issue #178).
    func loadActorAttachment(
        path: String,
        bone: String,
        skeleton: ActorSkeletonAsset?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        do {
            let model = try loadModel(
                path: path,
                terrainLODClipMask: nil,
                actorSkeleton: skeleton,
                explicitActorSkeleton: true,
                attachmentBone: bone
            )
            let key = try cacheKey(
                path: meshKey(for: path),
                terrainLODClipMask: nil,
                actorSkeletonKey: skeleton?.pathKey ?? "none",
                attachmentBone: bone
            )
            return .success(ActorRenderAsset(model: model, bounds: modelBounds[key]))
        } catch MeshLibraryError.fileNotFound {
            return .failure(.missing)
        } catch {
            return .failure(.invalid)
        }
    }

    func characterSkeleton() -> NIFSkeleton? {
        if triedCharacterSkeleton {
            return cachedCharacterSkeleton
        }
        triedCharacterSkeleton = true
        let path = "meshes\\actors\\character\\character assets\\skeleton.nif"
        guard
            let data = try? fileSystem.contents(forPath: path),
            let file = try? NIFFile(data: data),
            let skeleton = try? NIFSkeleton(file: file)
        else { return nil }
        cachedCharacterSkeleton = skeleton
        return skeleton
    }
}
