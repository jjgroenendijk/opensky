// The door a random door leads to: its saved link, else a free random door in one
// of its destinations. See docs/engine/random-doors.md.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// The door a random door leads to, and the links to store when it is new.
nonisolated struct RandomDoorTarget {
    let door: PlacedReference
    let arrival: PlacedReference.Placement
    let links: [(key: ReferenceKey, link: ReferenceDoorLink)]
}

nonisolated extension CellSceneBuilder.CellDoorTransitionBuilder {
    nonisolated func randomDoorTarget(
        source: PlacedReference,
        index: LoadOrderRecordIndex,
        state: WorldStateSnapshot
    ) throws -> RandomDoorTarget {
        let bases = owner.modelIndex.modelBaseIndexBuildingIfNeeded()
        guard
            let base = bases[source.base.rawValue], base.recordType == "DOOR",
            !base.details.randomTeleports.isEmpty,
            let sourceKey = ReferenceKey.resolve(source.formID, using: owner.formIDResolver)
        else {
            throw CellSceneError.doorHasNoTeleport(formID: source.formID)
        }
        if
            let linked = state[sourceKey]?.component(ReferenceDoorLink.self)?.door,
            let door = reference(linked, in: index)
        {
            return RandomDoorTarget(door: door, arrival: arrival(at: door, in: index), links: [])
        }
        guard
            let sourceLocation = owner.referenceBuilder.states.placedRecords
                .interiorCell(holding: source.formID)
                ?? index.worldFormID(containing: source.formID)
        else {
            throw CellSceneError.randomDoorLeadsNowhere(formID: source.formID)
        }
        var random = SplitMix64(
            seed: RandomDoorRules.seed(door: source.formID, sequence: state.sequence)
        )
        for destination in RandomDoorRules.tryOrder(base.details.randomTeleports, using: &random) {
            let candidates = references(at: destination, in: index).filter { candidate in
                candidate.formID != source.formID
                    && isFreeRandomDoor(
                        candidate,
                        listing: sourceLocation,
                        bases: bases,
                        state: state
                    )
            }
            guard
                let door = RandomDoorRules.pick(candidates, using: &random),
                let doorKey = ReferenceKey.resolve(door.formID, using: owner.formIDResolver)
            else { continue }
            return RandomDoorTarget(
                door: door,
                arrival: arrival(at: door, in: index),
                links: [
                    (sourceKey, ReferenceDoorLink(door: doorKey)),
                    (doorKey, ReferenceDoorLink(door: sourceKey))
                ]
            )
        }
        throw CellSceneError.randomDoorLeadsNowhere(formID: source.formID)
    }

    /// A random door that lists `location`, has no link yet, and is enabled.
    private func isFreeRandomDoor(
        _ reference: PlacedReference,
        listing location: FormID,
        bases: [UInt32: ModelBase],
        state: WorldStateSnapshot
    ) -> Bool {
        guard
            reference.teleportDestination == nil,
            let base = bases[reference.base.rawValue], base.recordType == "DOOR",
            base.details.randomTeleports.contains(location)
        else { return false }
        guard let key = ReferenceKey.resolve(reference.formID, using: owner.formIDResolver) else {
            return !reference.isInitiallyDisabled
        }
        let delta = state[key]
        guard delta?.component(ReferenceDoorLink.self) == nil else { return false }
        return delta?.component(ReferenceEnableState.self)?.isEnabled
            ?? !reference.isInitiallyDisabled
    }

    /// The references of an interior CELL, or of a WRLD's persistent cell.
    private func references(
        at destination: FormID,
        in index: LoadOrderRecordIndex
    ) -> [PlacedReference] {
        guard let found = index.record(withFormID: destination) else { return [] }
        let localized = owner.file.isLocalized
        var counts = BuildCounts()
        switch found.record.type {
        case "CELL":
            let cell = owner.interiorBuilder.findInteriorCell(
                formID: destination,
                localized: localized
            )
            return cell
                .map { owner.referenceBuilder.collectReferences(in: $0, counts: &counts) } ?? []
        case "WRLD":
            guard
                let name = owner.waterBuilder
                    .worldspaceIndexBuildingIfNeeded()[destination.rawValue]?
                    .editorID,
                let world = attempt({
                    try owner.records.worldChildrenGroup(editorID: name, localized: localized)
                })
            else { return [] }
            return persistentReferences(in: world, localized: localized)
        default:
            return []
        }
    }

    /// The door's teleport marker when it has one, else in front of the door.
    private func arrival(
        at door: PlacedReference,
        in index: LoadOrderRecordIndex
    ) -> PlacedReference.Placement {
        if let marker = door.details.links["XRTM"].flatMap({ reference($0, in: index) }) {
            return marker.placement
        }
        return RandomDoorRules.landing(before: door.placement)
    }

    private func reference(
        _ key: ReferenceKey,
        in index: LoadOrderRecordIndex
    ) -> PlacedReference? {
        guard
            case let .plugin(name, objectID) = key,
            let formID = owner.formIDResolver.localFormID(
                of: ResolvedFormID(plugin: name, objectID: objectID)
            )
        else { return nil }
        return reference(formID, in: index)
    }

    private func reference(_ formID: FormID, in index: LoadOrderRecordIndex) -> PlacedReference? {
        guard
            let found = index.record(withFormID: formID),
            found.record.type == "REFR", !found.record.isDeleted
        else { return nil }
        return attempt { try found.decode(PlacedReference.init(record:)) }
    }
}
