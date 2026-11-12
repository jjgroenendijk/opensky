// Where a preview stands: the spot and entry eye in a cell, and the cell that holds a reference.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

nonisolated extension CellPreviewPlaces {
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
            let placed = attempt({ try record.decode { try PlacedReference(record: $0) } }),
            let arrival = placed.teleportDestination?.placement
        else { return nil }
        return PlacedReference.Placement(
            position: arrival.position + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            rotation: arrival.rotation
        )
    }

    /// The plugins this builder reads, for record lookups by name.
    public var pluginLoadOrder: LoadOrderPlugins {
        owner.interiorBuilder.loadOrderIndexBuildingIfNeeded().loadOrder
    }

    /// The cell that holds a placed reference. An exterior reference gives the grid its
    /// position falls in, because a persistent one is stored in no grid cell.
    public func previewCell(holding reference: FormID) -> CellDirectoryEntry? {
        let index = owner.interiorBuilder.loadOrderIndexBuildingIfNeeded()
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
}
