// Door transitions and the exterior doors and persistent references of a worldspace.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyTerrain
public import OpenSkyWorldInterface
public import OpenSkyWorldState

nonisolated public struct DoorTransition: Sendable {
    public let sourceDoor: FormID
    public let destinationDoor: FormID
    public let destinationPlacement: PlacedReference.Placement
    public let scene: CellScene
    /// The worldspace of an exterior destination; nil for an interior.
    public var worldspaceEditorID: String?
}

nonisolated extension CellSceneBuilder.CellDoorTransitionBuilder {
    nonisolated private static func placedReference(
        _ found: LoadOrderRecord
    ) throws -> PlacedReference {
        do {
            return try found.decode(PlacedReference.init(record:))
        } catch {
            throw CellSceneError.malformedRecord(
                type: found.record.type,
                formID: found.formID,
                reason: String(describing: error)
            )
        }
    }

    /// Lightweight door probe over WRLD persistent refs. Their storage is the
    /// persistent CELL; physical REFR position supplies streamed-cell ownership.
    nonisolated public func exteriorDoors(
        worldspaceEditorID: String
    ) throws -> [(coordinate: CellCoordinate, door: PlacedDoor)] {
        let localized = owner.file.isLocalized
        let world = try owner.records.worldChildrenGroup(
            editorID: worldspaceEditorID, localized: localized
        )
        return persistentReferences(in: world, localized: localized)
            .filter { $0.teleportDestination != nil }
            .flatMap { ref -> [(coordinate: CellCoordinate, door: PlacedDoor)] in
                let doors = owner.assembler.interactions.resolveDoors(refs: [ref])
                let coordinate = CellGridManager.cellCoordinate(for: ref.placement.position)
                return doors.map { (coordinate, $0) }
            }
    }

    /// Merges local refs with the persistent CELL refs whose position lies in
    /// `coordinate`. Local teleport doors are filtered by position too.
    nonisolated public func exteriorReferences(
        local: [PlacedReference],
        world: FoundWorld,
        coordinate: CellCoordinate,
        localized: Bool
    ) -> [PlacedReference] {
        var byID: [FormID: PlacedReference] = [:]
        for ref in local where exteriorReference(ref, belongsTo: coordinate) {
            byID[ref.formID] = ref
        }
        for ref in persistentReferences(in: world, localized: localized)
            where CellGridManager.cellCoordinate(for: ref.placement.position) == coordinate
        {
            byID[ref.formID] = ref
        }
        return byID.values.sorted { $0.formID.rawValue < $1.formID.rawValue }
    }

    nonisolated private func exteriorReference(
        _ reference: PlacedReference,
        belongsTo coordinate: CellCoordinate
    ) -> Bool {
        guard reference.teleportDestination != nil else { return true }
        return CellGridManager.cellCoordinate(for: reference.placement.position) == coordinate
    }

    /// The worldspace's persistent references and actors by FormID, where an exterior
    /// `XESP` parent usually lives. Built once per worldspace.
    nonisolated func persistentParentPool(
        in world: FoundWorld,
        localized: Bool
    ) -> EnableParentPool {
        let key = world.formID.rawValue
        if let cached = owner.caches.exteriorPersistentPools[key] {
            return cached
        }
        let pool = owner.loadPhases.measure(.cellLookup) {
            var pool = EnableParentPool()
            for ref in persistentReferences(in: world, localized: localized) {
                pool.references[ref.formID] = ref
            }
            for actor in owner.actorBuilder.persistentActors(in: world, localized: localized) {
                pool.actors[actor.formID] = actor
            }
            return pool
        }
        owner.caches.exteriorPersistentPools[key] = pool
        return pool
    }

    nonisolated func persistentReferences(
        in world: FoundWorld,
        localized: Bool
    ) -> [PlacedReference] {
        let key = world.formID.rawValue
        if let cached = owner.caches.exteriorPersistentRefs[key] {
            return cached
        }
        var counts = BuildCounts()
        let refs = owner.recordIndex.persistentCell(in: world, localized: localized).map {
            owner.referenceBuilder.collectReferences(in: $0, counts: &counts)
        } ?? []
        owner.caches.exteriorPersistentRefs[key] = refs
        return refs
    }

    /// Source REFR XTEL -> destination door REFR -> owning CELL, then builds it.
    /// An exterior destination builds in the worldspace that holds the door, and
    /// `worldspaceEditorID` is only the fallback for a door outside any WRLD group.
    /// A door REFR that fails to decode throws `CellSceneError.malformedRecord`.
    nonisolated public func buildDoorTransition(
        from sourceDoor: FormID,
        worldspaceEditorID: String,
        state: WorldStateSnapshot = .empty
    ) throws -> DoorTransition {
        let index = owner.recordIndex.loadOrderIndexBuildingIfNeeded()
        guard
            let sourceRecord = index.record(withFormID: sourceDoor),
            sourceRecord.record.type == "REFR", !sourceRecord.record.isDeleted
        else {
            throw CellSceneError.doorReferenceNotFound(formID: sourceDoor)
        }
        let source = try Self.placedReference(sourceRecord)
        guard let teleport = source.teleportDestination else {
            throw CellSceneError.doorHasNoTeleport(formID: sourceDoor)
        }
        let destinationID = teleport.door
        guard
            let destinationRecord = index.record(withFormID: destinationID),
            destinationRecord.record.type == "REFR", !destinationRecord.record.isDeleted
        else {
            throw CellSceneError.teleportDestinationNotFound(formID: destinationID)
        }
        let destination = try Self.placedReference(destinationRecord)
        guard index.record(withFormID: destination.base)?.record.type == "DOOR" else {
            throw CellSceneError.teleportDestinationNotFound(formID: destinationID)
        }

        let scene: CellScene
        var worldspace: String?
        if
            let interior = owner.referenceBuilder.states.placedRecords
                .interiorCell(holding: destinationID)
        {
            scene = try owner.interiorBuilder.buildInteriorScene(cellFormID: interior, state: state)
        } else {
            let world = worldspaceName(holding: destinationID, in: index)
                ?? worldspaceEditorID
            let grid = CellGridManager.cellCoordinate(for: destination.placement.position)
            scene = try owner.buildScene(
                worldspaceEditorID: world,
                gridX: grid.x,
                gridY: grid.y,
                state: state
            )
            worldspace = world
        }
        return DoorTransition(
            sourceDoor: sourceDoor,
            destinationDoor: destinationID,
            destinationPlacement: teleport.placement,
            scene: scene,
            worldspaceEditorID: worldspace
        )
    }

    /// The editor ID of the WRLD whose world children hold `formID`.
    nonisolated func worldspaceName(
        holding formID: FormID,
        in index: LoadOrderRecordIndex
    ) -> String? {
        index.worldFormID(containing: formID)
            .flatMap { owner.waterBuilder.worldspaceIndexBuildingIfNeeded()[$0.rawValue]?.editorID }
    }
}
