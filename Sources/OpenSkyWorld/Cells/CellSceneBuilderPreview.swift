// One base record or mesh built alone, for preview renders. Each part comes from the
// path a cell build uses, so a preview draws what a cell would draw.
// Pipeline: docs/tools/preview-render.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
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

nonisolated extension CellSceneBuilder {
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
        let build = resolvedBuild(
            [CollectedActor(actor: actor, isPersistent: false)],
            malformed: [],
            parents: ActorEnableParents(),
            deltas: [:],
            started: DispatchTime.now().uptimeNanoseconds
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
        if let light = lightIndexBuildingIfNeeded()[base.rawValue] {
            let reference = PlacedReference(
                spawnedBase: base, placement: placement, scale: scale, count: 1,
                formID: Self.previewReference
            )
            var subject = light.details.model.map {
                previewMesh(path: $0.path, placement: placement, scale: scale)
            } ?? PreviewSubject()
            subject.pointLights = resolvePointLights([reference])
            return subject
        }
        guard
            let resolved = resolveBase(
                formID: base.rawValue,
                statIndex: statIndexBuildingIfNeeded(),
                modelBaseIndex: modelBaseIndexBuildingIfNeeded()
            )
        else { return nil }
        guard let path = resolved.modelPath else {
            var subject = PreviewSubject()
            subject.failures = ["\(resolved.recordType) \(base): no model"]
            return subject
        }
        return previewMesh(
            path: path, surface: surface(for: resolved.alternateTextures),
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

    /// Where a built cell places a reference; nil when it does not place it.
    public func previewPlacement(
        of reference: FormID, in scene: CellScene
    ) -> PlacedReference.Placement? {
        switch scene.references.entry(for: reference)?.record {
        case let .reference(placed)?: placed.placement
        case let .actor(actor)?: actor.placement
        case nil: nil
        }
    }

    /// Where a record stands when no reference names the spot: the middle of an
    /// exterior cell on its ground, or the floor below the middle of an interior.
    public func previewSpot(in scene: CellScene) -> PlacedReference.Placement {
        if case let .exterior(grid) = scene.location {
            let center = CellGridManager.cellCenter(of: grid)
            let ground = scene.terrainHeightField?.sample(at: SIMD2(center.x, center.y))?.height
            return PlacedReference.Placement(
                position: SIMD3(center.x, center.y, ground ?? center.z), rotation: .zero
            )
        }
        guard let bounds = scene.bounds else {
            return PlacedReference.Placement(position: .zero, rotation: .zero)
        }
        let middle = (bounds.min + bounds.max) * 0.5
        let floor = InteractionRay(
            origin: middle, direction: SIMD3(0, 0, -1), maximumDistance: middle.z - bounds.min.z + 1
        ).flatMap { ray in
            InteractionRaycaster.nearestHit(
                ray: ray, shapes: scene.staticCollision.candidates(overlapping: ray.bounds)
            )
        }
        return PlacedReference.Placement(
            position: SIMD3(middle.x, middle.y, floor?.position.z ?? bounds.min.z),
            rotation: .zero
        )
    }

    /// Where a player arriving through `door` stands, raised to eye height, with the
    /// arrival heading in `rotation.z`. Nil when the door has no teleport.
    public func previewEntryEye(door: FormID) -> PlacedReference.Placement? {
        guard
            let record = pluginLoadOrder.record(withFormID: door),
            let placed = try? record.decode({ try PlacedReference(record: $0) }),
            let arrival = placed.teleportDestination?.placement
        else { return nil }
        return PlacedReference.Placement(
            position: arrival.position + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            rotation: arrival.rotation
        )
    }

    /// The plugins this builder reads, for record lookups by name.
    public var pluginLoadOrder: LoadOrderPlugins {
        loadOrderIndexBuildingIfNeeded().loadOrder
    }

    /// The cell that holds a placed reference. An exterior reference gives the grid its
    /// position falls in, because a persistent one is stored in no grid cell.
    public func previewCell(holding reference: FormID) -> CellDirectoryEntry? {
        let index = loadOrderIndexBuildingIfNeeded()
        guard let cell = index.cellFormID(containing: reference) else { return nil }
        guard index.worldFormID(containing: reference) != nil else {
            return .interior(cell: cell, entryDoor: nil)
        }
        guard let placed = CellDirectory.exteriorPlacement(of: reference, in: index.loadOrder)
        else { return nil }
        return .exterior(
            cell: cell,
            worldspace: placed.worldspace,
            grid: CellGridManager.cellCoordinate(for: placed.placement.position)
        )
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
        let missingBefore = textures.missingPaths
        let transform = MatrixMath.placement(
            position: placement.position, rotation: placement.rotation, scale: scale
        )
        do {
            let model = try meshes.model(path: path, surface: surface)
            subject.placements = [RenderPlacement(
                model: model,
                transform: transform,
                bounds: meshes.bounds(forPath: path, surface: surface)?.transformed(by: transform)
            )]
        } catch {
            subject.failures.append("mesh \(path): \(String(describing: error))")
        }
        subject.failures += textures.missingPaths.subtracting(missingBefore).sorted()
            .map { "texture \($0): missing" }
        return subject
    }
}
