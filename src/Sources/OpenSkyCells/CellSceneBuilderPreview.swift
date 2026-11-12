// One base record or mesh built alone, for preview renders. Each part comes from the
// path a cell build uses, so a preview draws what a cell would draw.
// Pipeline: docs/tools/preview-render.md.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// A subject built alone: what it draws, and what did not resolve.
nonisolated public struct PreviewSubject {
    public var placements: [RenderPlacement] = []
    public var animations: [any RenderAnimation] = []
    public var pointLights: [RenderPointLight] = []
    /// One line per mesh, texture, or record that did not resolve.
    public var failures: [String] = []
    public var modelPath: String?
    /// A box that replaces the placements' bounds for framing.
    public var framing: ModelBounds?

    public init() {}

    public var bounds: ModelBounds? {
        framing ?? placements.compactMap(\.bounds).reduce(nil) { $0?.union($1) ?? $1 }
    }
}

nonisolated extension CellPreviewBuilder {
    /// The FormID the preview gives its one placed copy; outside every plugin's range.
    public static let previewReference = FormID(0xFF0F_FFF0)

    /// An NPC_ base, assembled as a cell build assembles an ACHR: body, head parts,
    /// face tint, and outfit.
    public func previewActor(
        base: FormID, placement: PlacedReference.Placement
    ) -> PreviewSubject {
        let actor = PlacedActor(
            spawnedBase: base, placement: placement, scale: 1, formID: Self.previewReference
        )
        let build = owner.actorBuilder.resolvedBuild(
            ([CollectedActor(actor: actor, isPersistent: false)], []),
            parents: ActorEnableParents(),
            deltas: [:],
            started: Stopwatch()
        )
        var subject = PreviewSubject()
        subject.placements = build.placements
        subject.animations = build.animations
        subject.failures = build.counts.failureReasons + build.counts.animationFailureReasons
        subject.framing = subject.bounds.map { Self.standingBox($0, feet: placement.position) }
        return subject
    }

    /// Skinned parts report a sphere around the feet, so an actor is framed as a
    /// standing box: from the feet up to the top of those bounds.
    static func standingBox(_ bounds: ModelBounds, feet: SIMD3<Float>) -> ModelBounds {
        let halfWidth: Float = 45
        let top = min(bounds.max.z, feet.z + 160)
        return ModelBounds(
            min: SIMD3(feet.x - halfWidth, feet.y - halfWidth, feet.z),
            max: SIMD3(feet.x + halfWidth, feet.y + halfWidth, max(top, feet.z + 64))
        )
    }

    /// A STAT, a model base (FURN, DOOR, CONT, ...), or a LIGH with its light. Nil when
    /// the base is none of these.
    public func previewObject(
        base: FormID, placement: PlacedReference.Placement, scale: Float = 1
    ) -> PreviewSubject? {
        if let light = owner.interiorLighting.lightIndexBuildingIfNeeded()[base.rawValue] {
            let reference = PlacedReference(
                spawnedBase: base, placement: placement, scale: scale, count: 1,
                formID: Self.previewReference
            )
            var subject = light.details.model.map {
                previewMesh(path: $0.path, placement: placement, scale: scale)
            } ?? PreviewSubject()
            subject.pointLights = owner.interiorLighting.resolvePointLights([reference])
            return subject
        }
        guard
            let resolved = owner.modelIndex.resolveBase(
                formID: base.rawValue,
                statIndex: owner.modelIndex.statIndexBuildingIfNeeded(),
                modelBaseIndex: owner.modelIndex.modelBaseIndexBuildingIfNeeded()
            )
        else { return nil }
        guard let path = resolved.modelPath else {
            var subject = PreviewSubject()
            subject.failures = ["\(resolved.recordType) \(base): no model"]
            return subject
        }
        return previewMesh(
            path: path, surface: owner.objectBuilder.surface(for: resolved),
            placement: placement, scale: scale
        )
    }

    /// A reference of a built cell, drawn alone at its own spot; nil when the cell does
    /// not place it. The camera frames its bounds.
    public func previewSubject(of reference: FormID, in scene: CellScene) -> PreviewSubject? {
        guard let entry = scene.references.entry(for: reference) else { return nil }
        switch entry.record {
        case let .actor(actor):
            return previewActor(base: actor.base, placement: actor.placement)
        case let .reference(placed):
            return previewObject(
                base: placed.base, placement: placed.placement, scale: placed.scale
            )
        }
    }

    /// One mesh by path, with the textures it names.
    public func previewMesh(
        path: String,
        surface: ModelSurfaceOverride = ModelSurfaceOverride(
            diffuseTexture: nil, normalTexture: nil, tint: nil
        ),
        placement: PlacedReference.Placement,
        scale: Float = 1
    ) -> PreviewSubject {
        var subject = PreviewSubject()
        subject.modelPath = path
        let missingBefore = owner.textures.missingPaths
        let transform = MatrixMath.placement(
            position: placement.position, rotation: placement.rotation, scale: scale
        )
        do {
            let model = try owner.meshes.model(path: path, surface: surface)
            subject.placements = [RenderPlacement(
                model: model,
                transform: transform,
                bounds: owner.meshes.bounds(forPath: path, surface: surface)?
                    .transformed(by: transform)
            )]
        } catch {
            subject.failures.append("mesh \(path): \(String(describing: error))")
        }
        subject.failures += owner.textures.missingPaths.subtracting(missingBefore).sorted()
            .map { "texture \($0): missing" }
        return subject
    }
}

nonisolated extension CellSceneBuilder {
    public var previewBuilder: CellPreviewBuilder {
        CellPreviewBuilder(owner: self)
    }

    public var previewPlaces: CellPreviewPlaces {
        CellPreviewPlaces(owner: self)
    }
}
