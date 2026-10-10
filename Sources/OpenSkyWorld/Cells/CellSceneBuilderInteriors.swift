// Interior cell build and door destination lookup. Block labels under the CELL
// top group are hints only, so the walk also tries siblings. Sources: UESP
// https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL and /REFR; xEdit
// UpdateInteriorCellGroup in
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbImplementation.pas

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated public struct DoorTransition: Sendable {
    public let sourceDoor: FormID
    public let destinationDoor: FormID
    public let destinationPlacement: PlacedReference.Placement
    public let scene: CellScene
}

nonisolated extension CellSceneBuilder {
    /// Lightweight door probe over WRLD persistent refs. Their storage is the
    /// persistent CELL; physical REFR position supplies streamed-cell ownership.
    nonisolated public func exteriorDoors(
        worldspaceEditorID: String
    ) throws -> [(coordinate: CellCoordinate, door: PlacedDoor)] {
        let localized = file.isLocalized
        let world = try worldChildrenGroup(
            editorID: worldspaceEditorID, localized: localized
        )
        return persistentReferences(in: world, localized: localized)
            .filter { $0.teleportDestination != nil }
            .flatMap { ref -> [(coordinate: CellCoordinate, door: PlacedDoor)] in
                let doors = resolveDoors(refs: [ref])
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
        if let cached = exteriorPersistentPools[key] {
            return cached
        }
        var pool = EnableParentPool()
        for ref in persistentReferences(in: world, localized: localized) {
            pool.references[ref.formID] = ref
        }
        for actor in persistentActors(in: world, localized: localized) {
            pool.actors[actor.formID] = actor
        }
        exteriorPersistentPools[key] = pool
        return pool
    }

    nonisolated private func persistentReferences(
        in world: FoundWorld,
        localized: Bool
    ) -> [PlacedReference] {
        let key = world.formID.rawValue
        if let cached = exteriorPersistentRefs[key] {
            return cached
        }
        var counts = BuildCounts()
        let refs = persistentCell(in: world, localized: localized).map {
            collectReferences(in: $0, counts: &counts)
        } ?? []
        exteriorPersistentRefs[key] = refs
        return refs
    }

    /// - Parameter state: runtime changes, applied as in the exterior build.
    nonisolated public func buildInteriorScene(
        cellFormID: FormID,
        state: WorldStateSnapshot = .empty
    ) throws -> CellScene {
        resetTouchedAssets()
        let localized = file.isLocalized
        guard let found = findInteriorCell(formID: cellFormID, localized: localized) else {
            throw CellSceneError.interiorCellNotFound(formID: cellFormID)
        }
        var counts = BuildCounts()
        let collected = collectTaggedReferences(in: found, counts: &counts)
        let refs = collected.map(\.reference)
        let location = CellSceneLocation.interior(cellFormID)
        let resolved = effectiveReferences(
            refs: refs, collected: collected, state: state, location: location, counts: &counts
        )
        let effective = resolved.references
        let collision = buildCollision(resolved: resolved, location: location)
        let instances = resolveInstances(refs: effective, counts: &counts)
        let actors = buildInteriorActors(
            cell: found, location: location, localized: localized,
            deltas: resolved.deltas, collision: collision.staticCollision,
            parents: ActorEnableParents(references: entriesByFormID(resolved.entries))
        )
        let lighting = buildInteriorLighting(cell: found.cell, references: effective)
        var scene = makeScene(
            found: found,
            grid: (x: 0, y: 0),
            instances: instances,
            // Interior water needs room bounds, not the exterior cell plane.
            geometry: CellGeometryBuild(
                location: location,
                doors: resolveDoors(refs: effective),
                interactions: resolveInteractions(refs: effective),
                terrain: nil,
                grass: nil,
                water: nil,
                sky: nil,
                lighting: lighting?.lighting,
                pointLights: lighting?.pointLights ?? [],
                staticCollision: collision.staticCollision,
                triggerVolumes: collision.triggerVolumes,
                dynamicBodies: collision.dynamicBodies,
                navmeshes: collectNavmeshes(in: found),
                actors: actors,
                referenceEntries: resolved.entries,
                stateSequence: state.sequence,
                vehicleFollowers: resolved.vehicleFollowers,
                rooms: RoomPortalGraphBuilder.graph(references: effective)
            ),
            counts: counts
        )
        scene.hazards = collectHazards(in: found, resolved: resolved)
        scene.imageSpace = found.cell.extras.imageSpace
        scene.assets = drainTouchedAssets()
        return scene
    }

    /// Source REFR XTEL -> destination door REFR -> owning CELL, then builds it.
    /// A door REFR that fails to decode throws `CellSceneError.malformedRecord`.
    nonisolated public func buildDoorTransition(
        from sourceDoor: FormID,
        worldspaceEditorID: String,
        state: WorldStateSnapshot = .empty
    ) throws -> DoorTransition {
        let index = loadOrderIndexBuildingIfNeeded()
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
        if let interior = placedRecords.interiorCell(holding: destinationID) {
            scene = try buildInteriorScene(cellFormID: interior, state: state)
        } else {
            let grid = CellGridManager.cellCoordinate(for: destination.placement.position)
            scene = try buildScene(
                worldspaceEditorID: worldspaceEditorID,
                gridX: grid.x,
                gridY: grid.y,
                state: state
            )
        }
        return DoorTransition(
            sourceDoor: sourceDoor,
            destinationDoor: destinationID,
            destinationPlacement: teleport.placement,
            scene: scene
        )
    }
}

nonisolated extension CellSceneBuilder {
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

    /// Groups whose labels match the object ID's ones and tens digits run first.
    /// The rest still run, because UESP warns labels may be stale.
    nonisolated private func findInteriorCell(
        formID: FormID,
        localized: Bool
    ) -> FoundCell? {
        let block = Int32(formID.objectID % 10)
        let subBlock = Int32((formID.objectID / 10) % 10)
        let base = file.topGroup(of: "CELL").flatMap { top in
            findInteriorCell(
                in: top,
                formID: formID.rawValue,
                expectedBlock: block,
                expectedSubBlock: subBlock,
                localized: localized
            )
        }
        guard let found = loadOrderCell(formID: formID, base: base), found.cell.isInterior
        else { return nil }
        return found
    }

    nonisolated private func findInteriorCell(
        in group: ESMGroup,
        formID: UInt32,
        expectedBlock: Int32,
        expectedSubBlock: Int32,
        localized: Bool
    ) -> FoundCell? {
        guard let children = childrenOrSkip(group) else { return nil }
        for (index, child) in children.enumerated() {
            guard
                case let .record(record) = child, record.type == "CELL",
                record.formID == formID,
                let cell = decodeOrSkip(record, using: {
                    try Cell(record: $0, localized: localized)
                }),
                cell.isInterior
            else { continue }
            return FoundCell(
                cell: cell,
                formID: record.formID,
                children: cellChildrenGroup(
                    following: index, in: children, cellFormID: record.formID
                )
            )
        }

        let groups = children.compactMap { child -> ESMGroup? in
            guard case let .group(group) = child else { return nil }
            let accepted = group.kind == .interiorCellBlock
                || group.kind == .interiorCellSubBlock
            return accepted ? group : nil
        }
        let prioritized = groups.sorted { lhs, rhs in
            let lhsMatch = interiorLabelMatches(
                lhs, block: expectedBlock, subBlock: expectedSubBlock
            )
            let rhsMatch = interiorLabelMatches(
                rhs, block: expectedBlock, subBlock: expectedSubBlock
            )
            return lhsMatch && !rhsMatch
        }
        for child in prioritized {
            let found = findInteriorCell(
                in: child,
                formID: formID,
                expectedBlock: expectedBlock,
                expectedSubBlock: expectedSubBlock,
                localized: localized
            )
            if let found {
                return found
            }
        }
        return nil
    }

    nonisolated private func interiorLabelMatches(
        _ group: ESMGroup,
        block: Int32,
        subBlock: Int32
    ) -> Bool {
        switch group.kind {
        case .interiorCellBlock: group.blockNumber == block
        case .interiorCellSubBlock: group.blockNumber == subBlock
        default: false
        }
    }

    nonisolated func loadOrderIndexBuildingIfNeeded() -> LoadOrderRecordIndex {
        if let loadOrderIndex {
            return loadOrderIndex
        }
        let index = LoadOrderRecordIndex(plugins: loadOrderPlugins, space: formIDResolver)
        loadOrderIndex = index
        return index
    }
}
