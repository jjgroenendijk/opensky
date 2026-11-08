// Where an assembled actor's models draw, and the box it culls by.

public import OpenSkyFormatsCore
public import OpenSkyRendering
public import OpenSkyRenderResources
public import OpenSkyWorldInterface
public import simd

nonisolated extension ActorAssembly where Asset == ActorRenderAsset {
    public var renderPlacements: [RenderPlacement] {
        renderPlacements(at: transform)
    }

    /// The same placements at a transform supplied from outside, because the player
    /// body moves every frame. A `reference` lets a walk or a vehicle move the body.
    /// `isCulled` false never culls, for a cut head that falls away from its bounds.
    public func renderPlacements(
        at transform: float4x4,
        faceMorphs: [ObjectIdentifier: FaceMorphBuffer] = [:],
        owner: UInt32 = 0,
        reference: UInt32 = 0,
        isCulled: Bool = true
    ) -> [RenderPlacement] {
        let posed = isCulled ? poseBounds?.transformed(by: transform) : nil
        return models.map {
            let morphs: [ObjectIdentifier: FaceMorphBuffer] =
                switch $0.role {
                case .faceGenHead, .headPart: faceMorphs
                default: [:]
                }
            return RenderPlacement(
                model: $0.asset.model,
                transform: transform,
                bounds: Self.isAttachment($0.role) ? nil : posed,
                referenceFormID: reference,
                faceMorphs: morphs,
                layer: .actors,
                owner: owner
            )
        }
    }

    private var poseBounds: ModelBounds? {
        ActorPoseBounds.containing(
            models.filter { !Self.isAttachment($0.role) }.compactMap(\.asset.bounds)
        )
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
