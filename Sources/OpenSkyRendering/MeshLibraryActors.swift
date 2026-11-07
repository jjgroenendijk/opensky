// Actor-facing model loading, split from MeshLibrary.swift for the strict-lint
// type-body length cap. Same cache, same build-queue confinement, same failure
// policy — this file only holds the three entry points actor assembly uses and
// the shared character-skeleton lookup behind them.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

nonisolated extension MeshLibrary {
    public func loadActorSkeleton(path: String) -> Result<ActorSkeletonAsset, ActorAssetFailure> {
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

    public func loadActorModel(
        path: String,
        skeleton: ActorSkeletonAsset?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        loadActorModel(
            path: path, skeleton: skeleton, surface: nil, bodyWeight: nil, keeping: nil
        )
    }

    public func loadActorModel(
        path: String,
        skeleton: ActorSkeletonAsset?,
        surface: ModelSurfaceOverride?,
        bodyWeight: Float?,
        keeping cut: DismemberCut?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        if let bone = rigidParentBone(path: path) {
            return loadActorAttachment(path: path, bone: bone, skeleton: skeleton)
        }
        let weight = bodyWeight
            .flatMap { BodyWeightBlend.thinPath(forHeavy: path) != nil ? $0 : nil }
        do {
            let model = try loadModel(
                path: path,
                terrainLODClipMask: nil,
                actorSkeleton: skeleton,
                explicitActorSkeleton: true,
                surface: surface,
                bodyWeight: weight,
                keeping: cut
            )
            let pathKey = try meshKey(for: path)
            let key = cacheKey(
                path: pathKey,
                terrainLODClipMask: nil,
                actorSkeletonKey: skeleton?.pathKey ?? "none",
                surface: surface,
                bodyWeight: weight,
                cut: cut
            )
            return .success(ActorRenderAsset(
                model: model.posableCopy(device: device), bounds: modelBounds[key]
            ))
        } catch MeshLibraryError.fileNotFound {
            return .failure(.missing)
        } catch {
            return .failure(.invalid)
        }
    }

    /// The `Prn` bone of a worn model with no skin, such as the vampire lord's cape: it
    /// hangs from that bone as a weapon does (docs/engine/actor-resolution.md). The file
    /// read here is kept for the decode, so a worn model is read from its archive once.
    func rigidParentBone(path: String) -> String? {
        guard let key = try? meshKey(for: path) else { return nil }
        if let known = rigidParentBones[key] {
            return known
        }
        let file = preparsed[key]
            ?? (try? fileSystem.contents(forPath: key)).flatMap { try? NIFFile(data: $0) }
        if preparsed[key] == nil, !actorDecodedPaths.contains(key) {
            preparsed[key] = file
        }
        let bone = file.flatMap { file in
            file.blocks.contains { $0.typeName.hasSuffix("SkinInstance") }
                ? nil : NIFStringExtraData.parentBone(in: file)
        }
        rigidParentBones[key] = .some(bone)
        return bone
    }

    public func loadActorAttachment(
        path: String,
        bone: String,
        skeleton: ActorSkeletonAsset?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        loadActorAttachment(path: path, bone: bone, subtree: nil, skeleton: skeleton)
    }

    /// A rigid model rewritten to ride `bone`, cached apart from the static version:
    /// a sword in a hand is a different mesh from one on a table.
    public func loadActorAttachment(
        path: String,
        bone: String,
        subtree: String?,
        skeleton: ActorSkeletonAsset?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        do {
            let model = try loadModel(
                path: path,
                terrainLODClipMask: nil,
                actorSkeleton: skeleton,
                explicitActorSkeleton: true,
                attachmentBone: bone,
                attachmentSubtree: subtree
            )
            let key = try cacheKey(
                path: meshKey(for: path),
                terrainLODClipMask: nil,
                actorSkeletonKey: skeleton?.pathKey ?? "none",
                attachmentBone: bone,
                attachmentSubtree: subtree
            )
            return .success(ActorRenderAsset(
                model: model.posableCopy(device: device), bounds: modelBounds[key]
            ))
        } catch MeshLibraryError.fileNotFound {
            return .failure(.missing)
        } catch {
            return .failure(.invalid)
        }
    }

    /// A head part with its TNAM textures and tint laid over the mesh. Texture
    /// paths are spelled as a TXST spells them.
    public func loadActorHeadPart(
        path: String,
        textures: HeadPartTextures,
        tint: SIMD3<Float>?,
        skeleton: ActorSkeletonAsset?,
        keeping cut: DismemberCut?
    ) -> Result<ActorRenderAsset, ActorAssetFailure> {
        let surface = ModelSurfaceOverride(
            diffuseTexture: textures.diffuse.flatMap(NIFShaderTextureSet.vfsKey(for:)),
            normalTexture: textures.normal.flatMap(NIFShaderTextureSet.vfsKey(for:)),
            tint: tint,
            detailTexture: textures.detail.flatMap(NIFShaderTextureSet.vfsKey(for:)),
            faceTintTexture: textures.faceTint
        )
        do {
            let model = try loadModel(
                path: path,
                terrainLODClipMask: nil,
                actorSkeleton: skeleton,
                explicitActorSkeleton: true,
                surface: surface,
                keeping: cut
            )
            let key = try cacheKey(
                path: meshKey(for: path),
                terrainLODClipMask: nil,
                actorSkeletonKey: skeleton?.pathKey ?? "none",
                surface: surface,
                cut: cut
            )
            return .success(ActorRenderAsset(
                model: model.posableCopy(device: device), bounds: modelBounds[key]
            ))
        } catch MeshLibraryError.fileNotFound {
            return .failure(.missing)
        } catch {
            return .failure(.invalid)
        }
    }

    public func characterSkeleton() -> NIFSkeleton? {
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
