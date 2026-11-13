// Interior cell build and door destination lookup. Block labels under the CELL
// top group are hints only, so the walk also tries siblings. Sources: UESP
// https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CELL and /REFR; xEdit
// UpdateInteriorCellGroup in
// https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbImplementation.pas

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyTerrain
import OpenSkyWorldInterface
public import OpenSkyWorldState

nonisolated extension CellSceneBuilder.CellInteriorBuilder {
    /// - Parameter state: runtime changes, applied as in the exterior build.
    nonisolated public func buildInteriorScene(
        cellFormID: FormID,
        state: WorldStateSnapshot = .empty
    ) throws -> CellScene {
        owner.assembler.resetTouchedAssets()
        let localized = owner.file.isLocalized
        guard let found = findInteriorCell(formID: cellFormID, localized: localized) else {
            throw CellSceneError.interiorCellNotFound(formID: cellFormID)
        }
        var counts = BuildCounts()
        let collected = owner.referenceBuilder.collectTaggedReferences(in: found, counts: &counts)
        let refs = collected.map(\.reference)
        let location = CellSceneLocation.interior(cellFormID)
        let resolved = owner.referenceBuilder.states.effectiveReferences(
            (refs, collected), state: state, location: location, counts: &counts
        )
        let effective = resolved.references
        let collision = owner.collisionBuilder.triggers
            .buildCollision(resolved: resolved, location: location)
        let instances = owner.records.instances.resolveInstances(refs: effective, counts: &counts)
        let actors = owner.actorBuilder.buildInteriorActors(
            cell: found, location: location, localized: localized,
            deltas: resolved.deltas, collision: collision.staticCollision,
            parents: ActorEnableParents(references: owner.referenceBuilder
                .states.entriesByFormID(resolved.entries))
        )
        let lighting = owner.interiorLighting
            .buildInteriorLighting(cell: found.cell, references: effective)
        var scene = owner.assembler.makeScene(
            cell: (found, (x: 0, y: 0)),
            instances: instances,
            geometry: CellGeometryBuild(
                location: location,
                doors: owner.assembler.interactions.resolveDoors(refs: effective),
                interactions: owner.assembler.interactions.resolveInteractions(refs: effective),
                terrain: nil,
                grass: nil,
                water: owner.waterBuilder.buildInteriorWater(found: found, instances: instances),
                sky: nil,
                lighting: lighting?.lighting,
                pointLights: lighting?.pointLights ?? [],
                staticCollision: collision.staticCollision,
                triggerVolumes: collision.triggerVolumes,
                dynamicBodies: collision.dynamicBodies,
                navmeshes: owner.referenceBuilder.collectNavmeshes(in: found),
                actors: actors,
                referenceEntries: resolved.entries,
                stateSequence: state.sequence,
                vehicleFollowers: resolved.vehicleFollowers,
                rooms: RoomPortalGraphBuilder.graph(references: effective)
            ),
            counts: counts
        )
        scene.imageSpace = found.cell.extras.imageSpace
        scene.waterVolumes = owner.waterVolumeBuilder.buildWaterVolumes(
            refs: effective, cellWater: nil, grid: nil, terrain: nil
        )
        return owner.objectBuilder.hazards.finished(
            scene,
            hazards: owner.objectBuilder.hazards.collectHazards(in: found, resolved: resolved),
            collision: collision
        )
    }
}

nonisolated extension CellSceneBuilder.CellInteriorBuilder {
    /// Groups whose labels match the object ID's ones and tens digits run first.
    /// The rest still run, because UESP warns labels may be stale.
    nonisolated private func findInteriorCell(
        formID: FormID,
        localized: Bool
    ) -> FoundCell? {
        let block = Int32(formID.objectID % 10)
        let subBlock = Int32((formID.objectID / 10) % 10)
        let base = owner.file.topGroup(of: "CELL").flatMap { top in
            findInteriorCell(
                in: top,
                formID: formID.rawValue,
                expected: (block, subBlock),
                localized: localized
            )
        }
        guard
            let found = owner.recordIndex.loadOrderCell(formID: formID, base: base),
            found.cell.isInterior
        else { return nil }
        return found
    }

    nonisolated private func findInteriorCell(
        in group: ESMGroup,
        formID: UInt32,
        expected: (block: Int32, subBlock: Int32),
        localized: Bool
    ) -> FoundCell? {
        guard let children = owner.records.childrenOrSkip(group) else { return nil }
        for (index, child) in children.enumerated() {
            guard
                case let .record(record) = child, record.type == "CELL",
                record.formID == formID,
                let cell = owner.records.decodeOrSkip(record, using: {
                    try Cell(record: $0, localized: localized)
                }),
                cell.isInterior
            else { continue }
            return FoundCell(
                cell: cell,
                formID: record.formID,
                children: owner.records.cellChildrenGroup(
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
                lhs, block: expected.block, subBlock: expected.subBlock
            )
            let rhsMatch = interiorLabelMatches(
                rhs, block: expected.block, subBlock: expected.subBlock
            )
            return lhsMatch && !rhsMatch
        }
        for child in prioritized {
            let found = findInteriorCell(
                in: child,
                formID: formID,
                expected: expected,
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
}

nonisolated extension CellSceneBuilder {
    public var interiorBuilder: CellSceneBuilder.CellInteriorBuilder {
        CellSceneBuilder.CellInteriorBuilder(owner: self)
    }

    var interiorLighting: CellSceneBuilder.CellInteriorLighting {
        CellSceneBuilder.CellInteriorLighting(owner: self)
    }

    public var doorTransitions: CellSceneBuilder.CellDoorTransitionBuilder {
        CellSceneBuilder.CellDoorTransitionBuilder(owner: self)
    }
}
