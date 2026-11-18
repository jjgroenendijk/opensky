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
    /// The owner a script set on a reference with `SetActorOwner` or `SetFactionOwner`.
    /// `.some(nil)` means a script cleared the owner; nil means no script set one.
    var scriptedOwner: ((ReferenceKey) -> ReferenceOwner??)?

    init(world: any CrimeSessionWorld, data: CrimeSessionData?) {
        self.world = world
        pluginName = data?.pluginName
        runtime = data?.runtime
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

    /// A script-set owner first, then the reference's own `XOWN`, then the owner of the
    /// cell it stands in, which a script may have set too.
    func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
        if let scripted = scriptedOwner?(key) {
            return scripted
        }
        let reference = world.references?.referenceEntry(key: key)?.placedReference
        if
            let authored = reference.flatMap(RecordOwnership.init(reference:)),
            let owner = ownership?.owner(of: authored)
        {
            return owner
        }
        return cellOwner(at: crimeCell(of: key))
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
        CrimeActor(
            base: actorBaseKey(of: key),
            memberships: world.factionMemberships(of: key) ?? ActorFactionState()
        )
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
