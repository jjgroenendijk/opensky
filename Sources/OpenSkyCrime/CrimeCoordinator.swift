// The shell of the crime domain: owns the bounty reporter, ownership, guard
// response, and the `World > Crime & Factions` panel state. It is the
// reporter's `CrimeWorld`. The rules live in `CrimeCore`, `CrimeRuntime`, and
// `GuardResponseState`. See docs/engine/coordinators.md and docs/engine/crime.md.

import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What the panel has selected. A nil selection falls back to the first
/// option the snapshot offers, which is what the popups show.
public struct CrimeFactionPanelState {
    public var bountyFaction: ReferenceKey?
    public var membershipFaction: ReferenceKey?
    public var vendorOverride: ReferenceKey?
    /// The actor the membership and vendor controls act on; nil is the player.
    public var subject: ReferenceKey?
    public var lastActionText = "No crime or faction action yet."
    /// Built once per load order.
    var options: CrimeFactionOptions?
}

/// Owns the crime runtimes and reads the world through `CrimeSessionWorld`.
/// Without a FACT index the reporter stays nil, and every take is honest.
@MainActor
public final class CrimeCoordinator {
    public private(set) var reporter: CrimeReporter?
    var ownership: OwnershipResolver?
    var crimeFactions: CrimeFactionResolver?
    var pluginName: String?
    /// Actors the player struck first. A later death counts as murder. Session
    /// state: a reloaded save restarts every fight.
    var assaultedActors: Set<ReferenceKey> = []
    /// So a trespass is noticed on arrival rather than once per frame.
    var lastPlayerCell: CellSceneLocation?
    public internal(set) var guards = GuardResponseState()
    /// Where each pursuing guard was last sent.
    var pursuitTargets: [ReferenceKey: SIMD3<Float>] = [:]
    /// A guard walks toward the player or holds the arrest talk. Fast travel
    /// refuses with `sNoFastTravelAlarm` meanwhile.
    public var isPlayerPursued: Bool {
        !pursuitTargets.isEmpty || guards.active != nil
    }

    public internal(set) var lastActionText = "No crime recorded yet."
    public internal(set) var lastGuardText = "No guard has acted yet."
    public var panel = CrimeFactionPanelState()

    weak var world: (any CrimeSessionWorld)?

    public init() {}

    public func attach(world: any CrimeSessionWorld) {
        self.world = world
    }

    /// `locations` is nil when the provider carries no LCTN index; then no
    /// place has a crime faction.
    public func wire(
        runtime: CrimeRuntime,
        locations: LocationStore?,
        pluginName: String
    ) {
        reporter = CrimeReporter(runtime: runtime, world: self)
        self.pluginName = pluginName
        // A new load order carries different factions for the panel to offer.
        panel.options = nil
        ownership = OwnershipResolver(factions: runtime.factions, pluginName: pluginName)
        crimeFactions = locations.map {
            CrimeFactionResolver(locations: $0, factions: runtime.factions)
        }
    }

    /// Separate from `wire`, because the perception pass needs a streamed
    /// world to watch.
    public func attachWitnesses(_ witnesses: any CrimeWitnessSource) {
        reporter?.witnesses = witnesses
    }

    // MARK: - Reading

    public func crimeGold(of faction: ReferenceKey) -> Int32 {
        reporter?.runtime.crimeGold(of: faction) ?? 0
    }

    /// Only the player's ledger travels: nothing gives an NPC a bounty, so a
    /// whole table would be a per-frame walk for rows that are all empty.
    public func conditionResolution() -> CrimeConditionResolution {
        guard let reporter else { return .empty }
        let ledger = reporter.runtime.ledger()
        return CrimeConditionResolution(
            factions: reporter.runtime.factions,
            sourcePlugin: pluginName,
            currentCrimeFaction: crimeFaction(in: world?.currentCellLocation),
            ledgers: ledger.isEmpty ? [:] : [.player: ledger]
        )
    }

    public func ownershipVerdict(on reference: ReferenceKey) -> OwnershipVerdict {
        reporter?.verdict(on: reference) ?? .unowned
    }

    public func theftBounty(of item: FormID, from reference: ReferenceKey) -> Int32 {
        reporter?.theftBounty(of: item, count: 1, from: reference) ?? 0
    }

    func factionName(_ faction: ReferenceKey) -> String {
        CrimeCore.factionName(faction, in: reporter?.runtime.factions)
    }

    // MARK: - Hooks

    /// The player's first blow against an actor that was not already hostile.
    /// Self-defense is no crime (<https://en.uesp.net/wiki/Skyrim:Crime>).
    public func reportAssault(
        on target: ReferenceKey,
        wasHostile: Bool,
        aggressor: ReferenceKey = .player
    ) {
        guard
            aggressor == .player,
            target != .player,
            !wasHostile,
            let reporter,
            assaultedActors.insert(target).inserted
        else { return }
        note(reporter.reportAssault(on: target), as: "Assault")
    }

    /// A death is murder when the player struck the victim first. A one-hit
    /// kill charges assault and murder (docs/engine/crime.md).
    public func reportMurder(of victim: ReferenceKey) {
        guard victim != .player, assaultedActors.contains(victim), let reporter else { return }
        note(reporter.reportMurder(of: victim), as: "Murder")
    }

    /// Runs every tick; the ownership lookup runs only when the cell changes.
    /// No warning or 30-second timer (docs/engine/crime.md).
    public func advanceTrespass() {
        let location = world?.currentCellLocation
        guard lastPlayerCell != location else { return }
        lastPlayerCell = location
        reportTrespass(in: location)
    }

    public func reportTrespass(in location: CellSceneLocation?) {
        guard let reporter, let owner = cellOwner(at: location) else { return }
        guard !crimeActor(.player).mayUse(owner) else { return }
        note(reporter.reportTrespass(in: location, owner: owner), as: "Trespass")
    }

    private func note(_ outcome: CrimeOutcome, as label: String) {
        lastActionText = CrimeCore.outcomeText(
            outcome, label: label, factionName: outcome.faction.map(factionName)
        )
    }

    private func cellOwner(at location: CellSceneLocation?) -> ReferenceOwner? {
        guard let location, let ownership = world?.cellOwnership(at: location) else { return nil }
        return self.ownership?.owner(of: ownership)
    }
}

extension CrimeCoordinator: CrimeWorld {
    /// A reference's own `XOWN` first, then the owner of the cell it stands in.
    public func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
        guard let ownership else { return nil }
        let reference = world?.references?.referenceEntry(key: key)?.placedReference
        let cell = crimeCell(of: key).flatMap { world?.cellOwnership(at: $0) }
        return ownership.owner(
            reference: reference.flatMap(RecordOwnership.init(reference:)),
            cell: cell
        )
    }

    public func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey? {
        guard
            let cell,
            let link = world?.cellLocationLink(at: cell),
            let resolvers = crimeFactions,
            let location = resolvers.locations.resolve(link.link, fromPlugin: link.plugin),
            let faction = resolvers.crimeFaction(of: location)
        else { return nil }
        return ReferenceKey(resolved: faction.id)
    }

    public func crimeCell(of key: ReferenceKey) -> CellSceneLocation? {
        world?.references?.cellLocation(of: key)
    }

    public func crimeItemValue(of item: FormID) -> Int64 {
        world?.itemValue(of: item) ?? 0
    }

    /// The player has no `NPC_` base here, so a base-owned reference is never
    /// theirs. Memberships are seeded first, so an actor nobody asked about
    /// answers from its authored `SNAM` run.
    public func crimeActor(_ key: ReferenceKey) -> CrimeActor {
        CrimeActor(
            base: actorBaseKey(of: key),
            memberships: world?.factionMemberships(of: key) ?? ActorFactionState()
        )
    }

    /// The runtime identity of the `NPC_` record `key` was placed from, which
    /// is what an `XOWN` actor link names.
    private func actorBaseKey(of key: ReferenceKey) -> ReferenceKey? {
        guard
            let base = world?.references?.referenceEntry(key: key)?.placedActor?.base,
            let pluginName,
            let resolved = reporter?.runtime.factions.resolvedID(base, fromPlugin: pluginName)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }
}
