// Interior CELL build + door destination resolution (M3.6). Interior cells
// live under CELL top-group block/sub-block groups instead of WRLD. Group
// labels are hints only: expected labels come from CELL FormID decimal ones
// + tens digits, but traversal falls back across siblings when labels lie.
//
// References:
// - UESP CELL: https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL
// - UESP REFR: https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/REFR
// - xEdit dev-4.1.6 wbImplementation.pas UpdateInteriorCellGroup:
//   https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbImplementation.pas

import Foundation

nonisolated struct DoorTransition {
    let sourceDoor: FormID
    let destinationDoor: FormID
    let destinationPlacement: PlacedReference.Placement
    let scene: CellScene
}

extension CellSceneBuilder {
    /// Lightweight door probe over WRLD persistent refs. Their storage CELL
    /// is (0,0); physical REFR position supplies streamed-cell ownership.
    nonisolated func exteriorDoors(
        worldspaceEditorID: String
    ) throws -> [(coordinate: CellCoordinate, door: PlacedDoor)] {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let world = try worldChildrenGroup(
            editorID: worldspaceEditorID, localized: localized
        )
        return persistentTeleportReferences(in: world.children, localized: localized)
            .flatMap { ref -> [(coordinate: CellCoordinate, door: PlacedDoor)] in
                let doors = resolveDoors(refs: [ref])
                let coordinate = CellGridManager.cellCoordinate(for: ref.placement.position)
                return doors.map { (coordinate, $0) }
            }
    }

    /// Merges local refs with XTEL refs from persistent CELL, filtering both
    /// by physical coordinate. Prevents persistent doors drawing in (0,0).
    nonisolated func exteriorReferences(
        local: [PlacedReference],
        world: ESMGroup,
        coordinate: CellCoordinate,
        localized: Bool
    ) -> [PlacedReference] {
        var byID: [FormID: PlacedReference] = [:]
        for ref in local where exteriorReference(ref, belongsTo: coordinate) {
            byID[ref.formID] = ref
        }
        for ref in persistentTeleportReferences(in: world, localized: localized) {
            guard exteriorReference(ref, belongsTo: coordinate) else { continue }
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

    nonisolated private func persistentTeleportReferences(
        in world: ESMGroup,
        localized: Bool
    ) -> [PlacedReference] {
        let key = world.parentFormID ?? 0
        if let cached = exteriorPersistentTeleportRefs[key] {
            return cached
        }
        guard
            let persistent = findCell(
                in: world, gridX: 0, gridY: 0, localized: localized
            )
        else {
            exteriorPersistentTeleportRefs[key] = []
            return []
        }
        var counts = BuildCounts()
        let refs = collectReferences(in: persistent.children, counts: &counts)
            .filter { $0.teleportDestination != nil }
        exteriorPersistentTeleportRefs[key] = refs
        return refs
    }

    nonisolated func buildInteriorScene(cellFormID: FormID) throws -> CellScene {
        _ = meshes.drainTouchedKeys()
        _ = textures.drainTouchedKeys()
        _ = collisionModels?.drainTouchedKeys()
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        guard let found = findInteriorCell(formID: cellFormID, localized: localized) else {
            throw CellSceneError.interiorCellNotFound(formID: cellFormID)
        }
        var counts = BuildCounts()
        let refs = collectReferences(in: found.children, counts: &counts)
        let location = CellSceneLocation.interior(cellFormID)
        let staticCollision = buildStaticCollision(refs: refs, location: location)
        let instances = resolveInstances(refs: refs, counts: &counts)
        let actors = buildInteriorActors(cellChildren: found.children, localized: localized)
        let lighting = buildInteriorLighting(cell: found.cell, references: refs)
        var scene = makeScene(
            found: found,
            grid: (x: 0, y: 0),
            instances: instances,
            // Interiors have no LAND or procedural sky. Interior water needs
            // room bounds rather than exterior's fixed cell plane -> deferred.
            geometry: CellGeometryBuild(
                location: location,
                doors: resolveDoors(refs: refs),
                terrain: nil,
                water: nil,
                sky: nil,
                lighting: lighting?.lighting,
                pointLights: lighting?.pointLights ?? [],
                staticCollision: staticCollision,
                actors: actors
            ),
            counts: counts
        )
        scene.assets = CellAssets(
            meshKeys: meshes.drainTouchedKeys()
                .union(collisionModels?.drainTouchedKeys() ?? []),
            textureKeys: textures.drainTouchedKeys()
        )
        return scene
    }

    /// Resolves source REFR XTEL -> destination door REFR -> owning CELL,
    /// then builds that exact cell on the same cache-confined queue.
    nonisolated func buildDoorTransition(
        from sourceDoor: FormID,
        worldspaceEditorID: String
    ) throws -> DoorTransition {
        guard
            let sourceRecord = ESMWalk.record(withFormID: sourceDoor.rawValue, in: file),
            sourceRecord.type == "REFR",
            let source = try? PlacedReference(record: sourceRecord)
        else {
            throw CellSceneError.doorReferenceNotFound(formID: sourceDoor)
        }
        guard let teleport = source.teleportDestination else {
            throw CellSceneError.doorHasNoTeleport(formID: sourceDoor)
        }
        let destinationID = teleport.door
        guard
            let destinationRecord = ESMWalk.record(withFormID: destinationID.rawValue, in: file),
            destinationRecord.type == "REFR",
            let destination = try? PlacedReference(record: destinationRecord),
            ESMWalk.record(withFormID: destination.base.rawValue, in: file)?.type == "DOOR"
        else {
            throw CellSceneError.teleportDestinationNotFound(formID: destinationID)
        }

        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let interior = findInteriorCell(
            containingReference: destinationID, localized: localized
        )
        let scene: CellScene
        if let interior {
            scene = try buildInteriorScene(cellFormID: FormID(interior.formID))
        } else {
            let grid = CellGridManager.cellCoordinate(for: destination.placement.position)
            scene = try buildScene(
                worldspaceEditorID: worldspaceEditorID,
                gridX: grid.x,
                gridY: grid.y
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

extension CellSceneBuilder {
    /// Expected group labels are decimal ones/tens digits of low-24-bit
    /// object ID. Matching-label groups run first for normal files; all other
    /// legal groups still run, because UESP warns labels may be stale.
    nonisolated private func findInteriorCell(
        formID: FormID,
        localized: Bool
    ) -> FoundCell? {
        guard let top = file.topGroup(of: "CELL") else { return nil }
        let block = Int32(formID.objectID % 10)
        let subBlock = Int32((formID.objectID / 10) % 10)
        return findInteriorCell(
            in: top,
            formID: formID.rawValue,
            expectedBlock: block,
            expectedSubBlock: subBlock,
            localized: localized
        )
    }

    nonisolated private func findInteriorCell(
        in group: ESMGroup,
        formID: UInt32,
        expectedBlock: Int32,
        expectedSubBlock: Int32,
        localized: Bool
    ) -> FoundCell? {
        guard let children = try? group.children() else { return nil }
        for (index, child) in children.enumerated() {
            guard
                case let .record(record) = child, record.type == "CELL",
                record.formID == formID,
                let cell = try? Cell(record: record, localized: localized), cell.isInterior
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

    nonisolated private func findInteriorCell(
        containingReference formID: FormID,
        localized: Bool
    ) -> FoundCell? {
        guard let top = file.topGroup(of: "CELL") else { return nil }
        return findCell(
            in: top,
            containingReference: formID.rawValue,
            allowedGroups: [.interiorCellBlock, .interiorCellSubBlock],
            localized: localized,
            requireInterior: true
        )
    }

    nonisolated private func findCell(
        in group: ESMGroup,
        containingReference formID: UInt32,
        allowedGroups: Set<ESMGroup.Kind>,
        localized: Bool,
        requireInterior: Bool
    ) -> FoundCell? {
        guard let children = try? group.children() else { return nil }
        for (index, child) in children.enumerated() {
            guard
                case let .record(record) = child, record.type == "CELL",
                let cell = try? Cell(record: record, localized: localized),
                cell.isInterior == requireInterior
            else { continue }
            let cellChildren = cellChildrenGroup(
                following: index, in: children, cellFormID: record.formID
            )
            if cellChildrenContains(reference: formID, group: cellChildren) {
                return FoundCell(cell: cell, formID: record.formID, children: cellChildren)
            }
        }
        for case let .group(child) in children {
            guard child.kind.map(allowedGroups.contains) == true else { continue }
            let found = findCell(
                in: child,
                containingReference: formID,
                allowedGroups: allowedGroups,
                localized: localized,
                requireInterior: requireInterior
            )
            if let found {
                return found
            }
        }
        return nil
    }

    nonisolated private func cellChildrenContains(
        reference formID: UInt32,
        group: ESMGroup?
    ) -> Bool {
        guard let group, let children = try? group.children() else { return false }
        for case let .group(child) in children {
            guard
                child.kind == .cellPersistentChildren || child.kind == .cellTemporaryChildren,
                let records = try? child.children()
            else { continue }
            let contains = records.contains { entry in
                guard case let .record(record) = entry else { return false }
                return record.type == "REFR" && record.formID == formID && !record.isDeleted
            }
            if contains {
                return true
            }
        }
        return false
    }
}
