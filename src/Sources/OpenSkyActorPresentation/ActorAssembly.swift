// Actor assembly: turn one resolved visual into race-skeleton-
// validated GPU assets at its ACHR world transform. Every upstream selection
// skip + asset failure remains reason-tagged. Assembly is renderable when at
// least one body or FaceGen model survives; floating skeleton-only actors are
// rejected. Cell discovery/lifecycle stays in milestone 5.5.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
public import OpenSkyWorldInterface
public import simd

nonisolated public protocol ActorAssetProvider {
    associatedtype Skeleton
    associatedtype Asset

    func loadActorSkeleton(path: String) -> Result<Skeleton, ActorAssetFailure>
    func loadActorModel(
        path: String,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
    /// `surface` lays per-shape textures over the model, such as ARMA swaps.
    /// `bodyWeight`, 0 to 1, blends a `_1.nif` model with its `_0.nif` sibling.
    /// `cut` keeps one side of a decapitation's dismember partitions.
    func loadActorModel(
        path: String,
        skeleton: Skeleton?,
        surface: ModelSurfaceOverride?,
        bodyWeight: Float?,
        keeping cut: DismemberCut?
    ) -> Result<Asset, ActorAssetFailure>
    /// A rigid model rewritten to ride one named skeleton bone. It caches under its
    /// own key, because the bone is part of the geometry.
    func loadActorAttachment(
        path: String,
        bone: String,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
    /// The same, drawing only the shapes below the model node `subtree`.
    func loadActorAttachment(
        path: String,
        bone: String,
        subtree: String?,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
    /// A head part with its texture set and tint applied, cut as `cut` says.
    func loadActorHeadPart(
        path: String,
        textures: HeadPartTextures,
        tint: SIMD3<Float>?,
        skeleton: Skeleton?,
        keeping cut: DismemberCut?
    ) -> Result<Asset, ActorAssetFailure>
}

nonisolated extension ActorAssetProvider {
    /// A provider that cannot cut a model draws all of it.
    public func loadActorAttachment(
        path: String,
        bone: String,
        subtree _: String?,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure> {
        loadActorAttachment(path: path, bone: bone, skeleton: skeleton)
    }

    /// A provider that cannot retexture loads the plain mesh.
    public func loadActorHeadPart(
        path: String,
        textures _: HeadPartTextures,
        tint _: SIMD3<Float>?,
        skeleton: Skeleton?,
        keeping _: DismemberCut?
    ) -> Result<Asset, ActorAssetFailure> {
        loadActorModel(path: path, skeleton: skeleton)
    }

    /// A provider that cannot retexture loads the plain mesh.
    public func loadActorModel(
        path: String,
        skeleton: Skeleton?,
        surface _: ModelSurfaceOverride?,
        bodyWeight _: Float?,
        keeping _: DismemberCut?
    ) -> Result<Asset, ActorAssetFailure> {
        loadActorModel(path: path, skeleton: skeleton)
    }
}

nonisolated public struct ActorAssembler<Provider: ActorAssetProvider> {
    public let provider: Provider

    public init(provider: Provider) {
        self.provider = provider
    }

    public func assemble(
        placed actor: PlacedActor,
        visual: ResolvedActorVisual
    ) -> ActorAssembly<Provider.Asset> {
        assemble(
            actor: actor.formID,
            transform: MatrixMath.placement(
                position: actor.placement.position,
                rotation: actor.placement.rotation,
                scale: actor.scale
            ),
            visual: visual
        )
    }

    /// Assembles an actor that has no ACHR behind it, such as the player. The
    /// transform comes from the character controller; everything else is the NPC
    /// path.
    public func assemble(
        actor: FormID,
        transform: float4x4,
        visual: ResolvedActorVisual
    ) -> ActorAssembly<Provider.Asset> {
        var skips = visual.skips.map {
            ActorAssemblySkip(subject: .appearance($0), reason: .appearance)
        }
        let skeleton = loadSkeleton(for: visual, skips: &skips)
        var models: [AssembledActorModel<Provider.Asset>] = []
        for part in visual.parts {
            append(
                path: part.modelPath,
                role: .body(part),
                surface: .skinned(part.surface, skinTone: visual.appearance.skinTone),
                bodyWeight: visual.appearance.weight / 100,
                cut: part.cut,
                skeleton: skeleton,
                models: &models,
                skips: &skips
            )
        }
        if visual.headSource == .assembled, !visual.headParts.parts.isEmpty {
            for part in visual.headParts.parts {
                appendHeadPart(
                    part, cut: visual.headCut, skeleton: skeleton, models: &models, skips: &skips
                )
            }
        } else if let facePath = visual.faceGenMeshPath {
            append(
                path: facePath,
                role: .faceGenHead(tintPath: visual.faceGenTintPath),
                surface: visual.faceGenSurface,
                cut: visual.headCut,
                skeleton: skeleton,
                models: &models,
                skips: &skips
            )
        }
        // Core geometry is decided before attachments join: a floating sword
        // over an actor with no body is exactly as wrong as the floating
        // skeleton-only actor this check already rejects.
        if models.isEmpty {
            skips.append(ActorAssemblySkip(
                subject: .actor(actor),
                reason: .noCoreGeometry
            ))
        } else {
            for attachment in visual.attachments {
                appendAttachment(
                    attachment, skeleton: skeleton, models: &models, skips: &skips
                )
            }
        }
        return ActorAssembly(
            actor: actor,
            visual: visual,
            transform: transform,
            models: models,
            skips: skips
        )
    }

    private func loadSkeleton(
        for visual: ResolvedActorVisual,
        skips: inout [ActorAssemblySkip]
    ) -> Provider.Skeleton? {
        guard let path = visual.skeletonPath else { return nil }
        switch provider.loadActorSkeleton(path: path) {
        case let .success(skeleton):
            return skeleton
        case let .failure(failure):
            skips.append(ActorAssemblySkip(
                subject: .skeleton(path: path),
                reason: reason(for: failure)
            ))
            return nil
        }
    }

    private func append(
        path: String,
        role: ActorModelRole,
        surface: ModelSurfaceOverride? = nil,
        bodyWeight: Float? = nil,
        cut: DismemberCut? = nil,
        skeleton: Provider.Skeleton?,
        models: inout [AssembledActorModel<Provider.Asset>],
        skips: inout [ActorAssemblySkip]
    ) {
        switch provider.loadActorModel(
            path: path, skeleton: skeleton, surface: surface, bodyWeight: bodyWeight,
            keeping: cut
        ) {
        case let .success(asset):
            models.append(AssembledActorModel(role: role, path: path, asset: asset))
        case let .failure(failure):
            skips.append(ActorAssemblySkip(
                subject: .model(role: role, path: path),
                reason: reason(for: failure)
            ))
        }
    }

    private func appendHeadPart(
        _ part: ResolvedHeadPart,
        cut: DismemberCut?,
        skeleton: Provider.Skeleton?,
        models: inout [AssembledActorModel<Provider.Asset>],
        skips: inout [ActorAssemblySkip]
    ) {
        let role = ActorModelRole.headPart(part)
        switch provider.loadActorHeadPart(
            path: part.modelPath,
            textures: HeadPartTextures(
                diffuse: part.diffuseTexture, normal: part.normalTexture,
                detail: part.detailTexture, faceTint: part.faceTintTexture
            ),
            tint: part.tint,
            skeleton: skeleton,
            keeping: cut
        ) {
        case let .success(asset):
            models.append(AssembledActorModel(role: role, path: part.modelPath, asset: asset))
        case let .failure(failure):
            skips.append(ActorAssemblySkip(
                subject: .model(role: role, path: part.modelPath),
                reason: reason(for: failure)
            ))
        }
    }

    private func appendAttachment(
        _ attachment: ResolvedAttachment,
        skeleton: Provider.Skeleton?,
        models: inout [AssembledActorModel<Provider.Asset>],
        skips: inout [ActorAssemblySkip]
    ) {
        let role = ActorModelRole.attachment(attachment)
        switch provider.loadActorAttachment(
            path: attachment.modelPath,
            bone: attachment.bone,
            subtree: attachment.subtree,
            skeleton: skeleton
        ) {
        case let .success(asset):
            models.append(
                AssembledActorModel(role: role, path: attachment.modelPath, asset: asset)
            )
        case let .failure(failure):
            skips.append(ActorAssemblySkip(
                subject: .model(role: role, path: attachment.modelPath),
                reason: reason(for: failure)
            ))
        }
    }

    private func reason(for failure: ActorAssetFailure) -> ActorAssemblySkip.Reason {
        switch failure {
        case .missing: .missingAsset
        case .invalid: .invalidAsset
        }
    }
}

nonisolated extension MeshLibrary: ActorAssetProvider {
    public typealias Skeleton = ActorSkeletonAsset
    public typealias Asset = ActorRenderAsset
}
