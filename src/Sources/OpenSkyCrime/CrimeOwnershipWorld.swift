// The crime reporter's world: who owns a reference or a cell, which crime faction
// polices a place, and who an actor is. See docs/engine/crime.md.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The `CrimeWorld` part of `CrimeCoordinator`. It holds the session world and the
/// load order's resolvers, not the coordinator.
final class CrimeOwnershipWorld: CrimeWorld {
    let world: any CrimeSessionWorld
    let ownership: OwnershipResolver?
    let crimeFactions: CrimeFactionResolver?
    let pluginName: String?
    let runtime: CrimeRuntime?
    let encounterZones: EncounterZoneStore?
    /// The owner a script set on a reference with `SetActorOwner` or `SetFactionOwner`.
    /// `.some(nil)` means a script cleared the owner; nil means no script set one.
    var scriptedOwner: ((ReferenceKey) -> ReferenceOwner??)?

    init(world: any CrimeSessionWorld, data: CrimeSessionData?) {
        self.world = world
        pluginName = data?.pluginName
        runtime = data?.runtime
        encounterZones = data?.encounterZones
        ownership = data.map {
            OwnershipResolver(factions: $0.runtime.factions, pluginName: $0.pluginName)
        }
        crimeFactions = data.flatMap { data in
            data.locations.map {
                CrimeFactionResolver(locations: $0, factions: data.runtime.factions)
            }
        }
    }

    /// A script-set owner first (`Cell.SetActorOwner`, `Cell.SetFactionOwner`), then
    /// the cell's own `XOWN`.
    func cellOwner(at location: CellSceneLocation?) -> ReferenceOwner? {
        if let scripted = scriptedCellOwner(at: location) {
            return scripted
        }
        guard let location, let ownership = world.cellOwnership(at: location) else { return nil }
        return self.ownership?.owner(of: ownership)
    }

    /// Only an interior is named by its `CELL` FormID here; an exterior is a grid.
    private func scriptedCellOwner(at location: CellSceneLocation?) -> ReferenceOwner?? {
        guard
            case let .interior(cell)? = location, let pluginName,
            let resolved = runtime?.factions.resolvedID(cell, fromPlugin: pluginName)
        else { return nil }
        return scriptedOwner?(ReferenceKey(resolved: resolved))
    }

    func favourAllowance(in faction: ReferenceKey) -> Int32? {
        runtime?.favourAllowance(in: faction) { [world] in world.factionMemberships(of: $0) }
    }

    /// The game's order: a script-set owner, the reference's own `XOWN`, the owner of the
    /// door at the other end of a teleport link, the encounter zone's owner, then the
    /// owner of the cell, which a script may have set too.
    func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
        if let scripted = scriptedOwner?(key) {
            return scripted
        }
        let reference = world.references?.referenceEntry(key: key)?.placedReference
        if let owner = reference.flatMap(ownOwner(of:)) {
            return owner
        }
        if let door = reference?.teleportDestination?.door, let owner = partnerOwner(door) {
            return owner
        }
        if let owner = zoneOwner(of: key) {
            return owner
        }
        return cellOwner(at: crimeCell(of: key))
    }

    private func ownOwner(of reference: PlacedReference) -> ReferenceOwner? {
        RecordOwnership(reference: reference).flatMap { ownership?.owner(of: $0) }
    }

    /// The far door's own owner, loaded or not.
    private func partnerOwner(_ door: FormID) -> ReferenceOwner? {
        let resident = world.references?.referenceEntry(formID: door)?.placedReference
        if let resident {
            return ownOwner(of: resident)
        }
        guard
            let pluginName,
            let resolved = runtime?.factions.resolvedID(door, fromPlugin: pluginName),
            let placed = world.references?.pluginPlacement(of: ReferenceKey(resolved: resolved))?
                .entry.placedReference
        else { return nil }
        return ownOwner(of: placed)
    }

    /// An `ECZN` owner. Only a reference's own required rank is checked, so the zone's
    /// rank is not.
    private func zoneOwner(of key: ReferenceKey) -> ReferenceOwner? {
        guard
            let link = world.encounterZoneLink(of: key),
            let zone = encounterZones?.resolve(link.link, fromPlugin: link.plugin),
            let owner = zone.zone.owner, !owner.isNull
        else { return nil }
        return ownership?.owner(
            of: RecordOwnership(owner: owner), inPlugin: zone.sourcePlugin
        )
    }

    func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey? {
        guard
            let cell,
            let link = world.cellLocationLink(at: cell),
            let resolvers = crimeFactions,
            let location = resolvers.locations.resolve(link.link, fromPlugin: link.plugin),
            let faction = resolvers.crimeFaction(of: location)
        else { return nil }
        return ReferenceKey(resolved: faction.id)
    }

    /// `.some(nil)` when the witnesses are known and none has a crime faction.
    func crimeFaction(ofWitnesses witnesses: [ReferenceKey]) -> ReferenceKey?? {
        let profiles = witnesses.compactMap { world.socialProfile(of: $0) }
        guard !profiles.isEmpty else { return nil }
        if
            let guardFaction = runtime?.factions.guardFactionKey,
            let policed = profiles.lazy.compactMap({
                GuardRecognition.policedFaction(of: $0, guardFaction: guardFaction)
            }).first
        {
            return .some(policed)
        }
        return .some(profiles.lazy.compactMap(\.crimeFaction).first)
    }

    func crimeCell(of key: ReferenceKey) -> CellSceneLocation? {
        world.references?.cellLocation(of: key)
    }

    func crimeItemValue(of item: FormID) -> Int64 {
        world.itemValue(of: item)
    }

    /// The player has no `NPC_` base here, so a base-owned reference is never
    /// theirs. Memberships are seeded first, so an actor nobody asked about
    /// answers from its authored `SNAM` run.
    func crimeActor(_ key: ReferenceKey) -> CrimeActor {
        var actor = CrimeActor(
            base: actorBaseKey(of: key),
            memberships: world.factionMemberships(of: key) ?? ActorFactionState()
        )
        actor.ignoresRequiredRank = key == .player
        return actor
    }

    /// The runtime identity of the `NPC_` record `key` was placed from, which
    /// is what an `XOWN` actor link names.
    private func actorBaseKey(of key: ReferenceKey) -> ReferenceKey? {
        guard
            let base = world.references?.referenceEntry(key: key)?.placedActor?.base,
            let pluginName,
            let resolved = runtime?.factions.resolvedID(base, fromPlugin: pluginName)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }
}
