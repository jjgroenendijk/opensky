// Actor assembly: turn one resolved visual into race-skeleton-
// validated GPU assets at its ACHR world transform. Every upstream selection
// skip + asset failure remains reason-tagged. Assembly is renderable when at
// least one body or FaceGen model survives; floating skeleton-only actors are
// rejected. Cell discovery/lifecycle stays in milestone 5.5.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import simd

nonisolated public protocol ActorAssetProvider {
    associatedtype Skeleton
    associatedtype Asset

    func loadActorSkeleton(path: String) -> Result<Skeleton, ActorAssetFailure>
    func loadActorModel(
        path: String,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
    /// A rigid model rewritten to ride one named skeleton bone. It caches under its
    /// own key, because the bone is part of the geometry.
    func loadActorAttachment(
        path: String,
        bone: String,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
    /// A head part with its texture set and tint applied.
    func loadActorHeadPart(
        path: String,
        diffuseTexture: String?,
        normalTexture: String?,
        tint: SIMD3<Float>?,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure>
}

nonisolated extension ActorAssetProvider {
    /// A provider that cannot retexture loads the plain mesh.
    public func loadActorHeadPart(
        path: String,
        diffuseTexture _: String?,
        normalTexture _: String?,
        tint _: SIMD3<Float>?,
        skeleton: Skeleton?
    ) -> Result<Asset, ActorAssetFailure> {
        loadActorModel(path: path, skeleton: skeleton)
    }
}

nonisolated public enum ActorModelRole: Equatable, Sendable {
    case body(ResolvedBodyPart)
    case faceGenHead(tintPath: String?)
    /// A drawn weapon or an idle prop riding a bone.
    case attachment(ResolvedAttachment)
    /// One part of an assembled head.
    case headPart(ResolvedHeadPart)
}

nonisolated public struct ActorAssemblySkip: Equatable, Sendable {
    nonisolated public enum Subject: Equatable, Sendable {
        case appearance(AppearanceSkip)
        case skeleton(path: String)
        case model(role: ActorModelRole, path: String)
        case actor(FormID)
    }

    nonisolated public enum Reason: Equatable, Sendable {
        case appearance
        case missingAsset
        case invalidAsset
        case noCoreGeometry
    }

    public let subject: Subject
    public let reason: Reason
}

nonisolated public struct AssembledActorModel<Asset> {
    public let role: ActorModelRole
    public let path: String
    public let asset: Asset
}

nonisolated public struct ActorAssembly<Asset> {
    public let actor: FormID
    public let visual: ResolvedActorVisual
    public let transform: float4x4
    public let models: [AssembledActorModel<Asset>]
    public let skips: [ActorAssemblySkip]

    public var isRenderable: Bool {
        !models.isEmpty
    }
}

nonisolated extension AssembledActorModel: Sendable where Asset: Sendable {}

nonisolated extension ActorAssembly: Sendable where Asset: Sendable {}

nonisolated public struct ActorAssembler<Provider: ActorAssetProvider> {
    public let provider: Provider

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
                skeleton: skeleton,
                models: &models,
                skips: &skips
            )
        }
        if visual.headSource == .assembled, !visual.headParts.parts.isEmpty {
            for part in visual.headParts.parts {
                appendHeadPart(part, skeleton: skeleton, models: &models, skips: &skips)
            }
        } else if let facePath = visual.faceGenMeshPath {
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

    private func appendHeadPart(
        _ part: ResolvedHeadPart,
        skeleton: Provider.Skeleton?,
        models: inout [AssembledActorModel<Provider.Asset>],
        skips: inout [ActorAssemblySkip]
    ) {
        let role = ActorModelRole.headPart(part)
        switch provider.loadActorHeadPart(
            path: part.modelPath,
            diffuseTexture: part.diffuseTexture,
            normalTexture: part.normalTexture,
            tint: part.tint,
            skeleton: skeleton
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

nonisolated extension MeshLibrary: ActorAssetProvider {
    public typealias Skeleton = ActorSkeletonAsset
    public typealias Asset = ActorRenderAsset
}

nonisolated extension ActorAssembly where Asset == ActorRenderAsset {
    public var renderPlacements: [RenderPlacement] {
        renderPlacements(at: transform)
    }

    /// The same placements at a transform supplied from outside, because the player
    /// body moves every frame.
    public func renderPlacements(
        at transform: float4x4,
        faceMorphs: [ObjectIdentifier: FaceMorphBuffer] = [:],
        owner: UInt32 = 0
    ) -> [RenderPlacement] {
        models.map {
            let morphs: [ObjectIdentifier: FaceMorphBuffer] =
                switch $0.role {
                case .faceGenHead, .headPart: faceMorphs
                default: [:]
                }
            return RenderPlacement(
                model: $0.asset.model,
                transform: transform,
                bounds: Self.isAttachment($0.role)
                    ? nil
                    : $0.asset.bounds?.transformed(by: transform),
                faceMorphs: morphs,
                layer: .actors,
                owner: owner
            )
        }
    }

    public var worldBounds: ModelBounds? {
        models.filter { !Self.isAttachment($0.role) }
            .compactMap { $0.asset.bounds?.transformed(by: transform) }
            .reduce(nil) { result, bounds in result.map { $0.union(bounds) } ?? bounds }
    }

    /// Attachment bounds sit at the weapon's own origin, not at the hand, so they
    /// cannot be used for culling or the actor's box. Nil means never culled, which
    /// is fine for one small mesh.
    private static func isAttachment(_ role: ActorModelRole) -> Bool {
        if case .attachment = role {
            return true
        }
        return false
    }
}
