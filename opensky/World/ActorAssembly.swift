// Actor assembly (milestone 5.4): turn one resolved visual into race-skeleton-
// validated GPU assets at its ACHR world transform. Every upstream selection
// skip + asset failure remains reason-tagged. Assembly is renderable when at
// least one body or FaceGen model survives; floating skeleton-only actors are
// rejected. Cell discovery/lifecycle stays in milestone 5.5.

import Foundation
import simd

nonisolated enum ActorAssetFailure: Error, Equatable {
    case missing
    case invalid
}

nonisolated protocol ActorAssetProvider {
    associatedtype Skeleton
    associatedtype Asset

    func loadActorSkeleton(path: String) -> Result<Skeleton, ActorAssetFailure>
    func loadActorModel(
        path: String,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
    /// A rigid model rewritten to ride one named skeleton bone (issue #178).
    /// Separate from `loadActorModel` because the result is a different asset
    /// even for the same path — the bone is part of the geometry — and so must
    /// cache under its own key.
    func loadActorAttachment(
        path: String,
        bone: String,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
}

nonisolated enum ActorModelRole: Equatable {
    case body(ResolvedBodyPart)
    case faceGenHead(tintPath: String?)
    /// A drawn weapon riding a hand bone.
    case attachment(ResolvedAttachment)
}

nonisolated struct ActorAssemblySkip: Equatable {
    nonisolated enum Subject: Equatable {
        case appearance(AppearanceSkip)
        case skeleton(path: String)
        case model(role: ActorModelRole, path: String)
        case actor(FormID)
    }

    nonisolated enum Reason: Equatable {
        case appearance
        case missingAsset
        case invalidAsset
        case noCoreGeometry
    }

    let subject: Subject
    let reason: Reason
}

nonisolated struct AssembledActorModel<Asset> {
    let role: ActorModelRole
    let path: String
    let asset: Asset
}

nonisolated struct ActorAssembly<Asset> {
    let actor: FormID
    let base: FormID
    let visual: ResolvedActorVisual
    let transform: float4x4
    let models: [AssembledActorModel<Asset>]
    let skips: [ActorAssemblySkip]

    var isRenderable: Bool {
        !models.isEmpty
    }
}

nonisolated struct ActorAssembler<Provider: ActorAssetProvider> {
    let provider: Provider

    func assemble(
        placed actor: PlacedActor,
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
                skeleton: skeleton,
                models: &models,
                skips: &skips
            )
        }
        if let facePath = visual.faceGenMeshPath {
            append(
                path: facePath,
                role: .faceGenHead(tintPath: visual.faceGenTintPath),
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
                subject: .actor(actor.formID),
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
            actor: actor.formID,
            base: actor.base,
            visual: visual,
            transform: MatrixMath.placement(
                position: actor.placement.position,
                rotation: actor.placement.rotation,
                scale: actor.scale
            ),
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
        skeleton: Provider.Skeleton?,
        models: inout [AssembledActorModel<Provider.Asset>],
        skips: inout [ActorAssemblySkip]
    ) {
        switch provider.loadActorModel(path: path, skeleton: skeleton) {
        case let .success(asset):
            models.append(AssembledActorModel(role: role, path: path, asset: asset))
        case let .failure(failure):
            skips.append(ActorAssemblySkip(
                subject: .model(role: role, path: path),
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
            path: attachment.modelPath, bone: attachment.bone, skeleton: skeleton
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

nonisolated struct ActorSkeletonAsset {
    let pathKey: String
    let skeleton: NIFSkeleton
}

nonisolated struct ActorRenderAsset {
    let model: RenderModel
    let bounds: ModelBounds?
}

nonisolated extension MeshLibrary: ActorAssetProvider {
    typealias Skeleton = ActorSkeletonAsset
    typealias Asset = ActorRenderAsset
}

nonisolated extension ActorAssembly where Asset == ActorRenderAsset {
    var renderPlacements: [RenderPlacement] {
        models.map {
            RenderPlacement(
                model: $0.asset.model,
                transform: transform,
                bounds: Self.isAttachment($0.role)
                    ? nil
                    : $0.asset.bounds?.transformed(by: transform)
            )
        }
    }

    var worldBounds: ModelBounds? {
        models.filter { !Self.isAttachment($0.role) }
            .compactMap { $0.asset.bounds?.transformed(by: transform) }
            .reduce(nil) { result, bounds in result.map { $0.union(bounds) } ?? bounds }
    }

    /// An attachment's model bounds sit at the weapon's own origin, not where
    /// the hand bone carries it, so pushing them through the actor transform
    /// would name a box the geometry is never in. Culling attachments on it
    /// would blink a drawn weapon out at the wrong moment, and folding it into
    /// the actor's world bounds would move the actor's box. Nil bounds means
    /// never culled, which for one small mesh per armed actor is the right
    /// trade until attachment bounds follow the pose (M15 draw/sheath).
    private static func isAttachment(_ role: ActorModelRole) -> Bool {
        if case .attachment = role {
            return true
        }
        return false
    }
}
