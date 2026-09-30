// Session wiring for crime: builds the crime runtime over the provider's FACT
// and LCTN indexes, answers `CrimeWorld`, and routes takes, blows, and deaths
// into the bounty ledger. `crimeOwner(of:)` runs once per take, not per frame,
// and is not cached: a quest can change ownership at any time. The witness
// check reads the perception state, so a take costs no raycast.

import AppKit
import OpenSkyActorsInterface
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFactions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPerception
import OpenSkyWorld
import OpenSkyWorldState

/// Crime state the controller owns. Extensions cannot add stored properties, so
/// it lives as one value on `GameViewController`.
struct CrimeBridgeState {
    /// The ledger, the pricing and the hooks over them, built by `wireCrime`
    /// when the provider can supply a FACT index. Nil without game data, and
    /// then every take is an honest one — which is what this engine did before
    /// this milestone.
    var reporter: CrimeReporter?
    /// Resolves an `XOWN` link to an actor or a faction owner. Nil beside a nil
    /// reporter, for the same reason.
    var ownership: OwnershipResolver?
    /// Walks a cell's location parent chain to the crime faction that answers
    /// for it.
    var crimeFactions: CrimeFactionResolver?
    /// Actors the player struck first this session. The second blow of a fight is
    /// not a second assault, and a later death counts as murder. Session state, not
    /// a component: a reloaded save restarts every fight.
    var assaultedActors: Set<ReferenceKey> = []
    /// Cell the player was last seen in, so a trespass is noticed on arrival
    /// rather than once per frame for as long as they stay.
    var lastPlayerCell: CellSceneLocation?
    /// Who is mid-confrontation, who is cooling off, and which factions the
    /// player resisted.
    var guards = GuardResponseState()
    /// Where each pursuing guard was last sent, so a pursuit repaths only once
    /// the player has moved away from it rather than every frame.
    var pursuitTargets: [ReferenceKey: SIMD3<Float>] = [:]
    /// Human-readable result of the last crime the session recorded.
    var lastActionText = "No crime recorded yet."
    /// Human-readable result of the last guard action.
    var lastGuardText = "No guard has acted yet."
    /// What the `World > Crime & Factions` panel has selected.
    var panel = CrimeFactionPanelState()
}

extension GameViewController {
    /// Builds the crime runtime over the provider's FACT and LCTN indexes.
    ///
    /// Wired after `wireFactions` and `wireWorldItems`, because it hands the
    /// reporter to the world-item runtime those two already built and reads the
    /// same FACT store the hostility derivation does.
    func wireCrime(provider: any WorldDataProviding) {
        guard
            let factionStore = (provider as? FactionDataProviding)?.factionStore,
            let pluginName = (provider as? MagicDataProviding)?.magicItemPluginName
        else { return }
        let reporter = CrimeReporter(
            runtime: CrimeRuntime(store: worldState, factions: factionStore),
            world: self
        )
        crime.reporter = reporter
        // A new load order carries different factions for the panel to offer.
        crime.panel.options = nil
        crime.ownership = OwnershipResolver(factions: factionStore, pluginName: pluginName)
        if let locations = (provider as? LocationDataProviding)?.locationStore {
            crime.crimeFactions = CrimeFactionResolver(
                locations: locations,
                factions: factionStore
            )
        }
        worldItems.runtime?.crime = reporter
    }

    /// Hands the perception pass to the crime runtime once it exists, so a
    /// witnessed crime is one the pass actually saw.
    ///
    /// Separate from `wireCrime` because the two are built at different points:
    /// the crime runtime needs only the record indexes, while the perception
    /// pass needs a streamed world to watch.
    func attachCrimeWitnesses(perception: PerceptionRuntime?) {
        crime.reporter?.witnesses = PerceptionCrimeWitnesses(
            perception: perception,
            isAlive: { [weak self] key in
                self?.worldState.component(ActorDeathState.self, for: key)?.isDead != true
            }
        )
    }

    // MARK: - Reading

    /// Crime gold the player owes one faction.
    func crimeGold(of faction: ReferenceKey) -> Int32 {
        crime.reporter?.runtime.crimeGold(of: faction) ?? 0
    }

    /// Crime ledgers as the condition machinery reads them, which is what
    /// `GetCrimeGold` answers from.
    ///
    /// Only the player's ledger travels: nothing in this engine gives an NPC a
    /// bounty, so building the whole table would be a per-frame walk of every
    /// resident actor for rows that are all empty.
    func crimeConditionResolution() -> CrimeConditionResolution {
        guard let reporter = crime.reporter else { return .empty }
        let ledger = reporter.runtime.ledger()
        return CrimeConditionResolution(
            factions: reporter.runtime.factions,
            sourcePlugin: (worldData as? MagicDataProviding)?.magicItemPluginName,
            currentCrimeFaction: crimeFaction(in: streamer?.currentCellLocation),
            ledgers: ledger.isEmpty ? [:] : [.player: ledger]
        )
    }

    /// What taking the reference under the crosshair would be.
    func ownershipVerdict(on reference: ReferenceKey) -> OwnershipVerdict {
        crime.reporter?.verdict(on: reference) ?? .unowned
    }

    // MARK: - Hooks

    /// Records the player's first blow against an actor that was not already
    /// hostile. Every landed blow passes through `reportScriptHit`. Self-defense is
    /// no crime (<https://en.uesp.net/wiki/Skyrim:Crime>), and only the first strike
    /// of a fight counts.
    func reportPlayerAssault(
        on target: ReferenceKey,
        wasHostile: Bool,
        aggressor: ReferenceKey = .player
    ) {
        guard
            aggressor == .player,
            target != .player,
            !wasHostile,
            let reporter = crime.reporter,
            crime.assaultedActors.insert(target).inserted
        else { return }
        note(reporter.reportAssault(on: target), as: "Assault")
    }

    /// Records a death as murder when the player struck the victim first. The death
    /// sweep does not know who emptied health, so `assaultedActors` is the
    /// attribution. A one-hit kill charges assault and murder, because the blow is
    /// reported before the death. See docs/engine/crime.md.
    func reportPlayerMurder(of victim: ReferenceKey) {
        guard
            victim != .player,
            crime.assaultedActors.contains(victim),
            let reporter = crime.reporter
        else { return }
        note(reporter.reportMurder(of: victim), as: "Murder")
    }

    /// Notices the player arriving somewhere an owner has not allowed. Runs every
    /// tick, but the ownership lookup runs only when the cell changes. The trespass
    /// is recorded on arrival, without the game's warning and 30-second timer
    /// (docs/engine/crime.md).
    func advanceCrimeTrespass() {
        let location = streamer?.currentCellLocation
        guard crime.lastPlayerCell != location else { return }
        crime.lastPlayerCell = location
        reportPlayerTrespass(in: location)
    }

    /// Records the player standing somewhere an owner has not let them be.
    func reportPlayerTrespass(in location: CellSceneLocation?) {
        guard let reporter = crime.reporter else { return }
        guard let owner = cellOwner(at: location) else { return }
        guard !crimeActor(.player).mayUse(owner) else { return }
        note(reporter.reportTrespass(in: location, owner: owner), as: "Trespass")
    }

    /// Records one outcome in the panel line, naming the refusal when there was
    /// one so a zero bounty never reads as a crime nobody noticed.
    private func note(_ outcome: CrimeOutcome, as label: String) {
        let name = outcome.faction
            .flatMap { crime.reporter?.runtime.factions.faction(key: $0)?.displayName }
            ?? "nobody"
        guard let refusal = outcome.refusal else {
            crime.lastActionText = "\(label): \(outcome.gold) bounty with \(name)."
            return
        }
        crime.lastActionText = "\(label): no bounty with \(name) — \(refusal.rawValue)."
    }

    /// The `XOWN` in force on one cell, resolved to an owner.
    private func cellOwner(at location: CellSceneLocation?) -> ReferenceOwner? {
        guard
            let location,
            let scene = streamer?.residentScene(at: location),
            let ownership = scene.owner
        else { return nil }
        return crime.ownership?.owner(of: ownership)
    }
}

extension GameViewController: CrimeWorld {
    /// A reference's own `XOWN` first, then the owner of the cell it stands in.
    func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
        guard let resolver = crime.ownership else { return nil }
        let reference = streamer?.referenceEntry(key: key)?.placedReference
        let location = streamer?.cellLocation(of: key)
        return resolver.owner(
            reference: reference.flatMap(RecordOwnership.init(reference:)),
            cell: location.flatMap { streamer?.residentScene(at: $0)?.owner }
        )
    }

    func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey? {
        guard
            let cell,
            let scene = streamer?.residentScene(at: cell),
            let link = scene.locationLink,
            let plugin = scene.ownerPluginName,
            let resolvers = crime.crimeFactions,
            let location = resolvers.locations.resolve(link, fromPlugin: plugin),
            let faction = resolvers.crimeFaction(of: location)
        else { return nil }
        return ReferenceKey(resolved: faction.id)
    }

    func crimeCell(of key: ReferenceKey) -> CellSceneLocation? {
        streamer?.cellLocation(of: key)
    }

    func crimeItemValue(of item: FormID) -> Int64 {
        Int64(
            worldItems.runtime?.inventory.baselines.items.definition(item)?.value ?? 0
        )
    }

    /// The player has no NPC_ base in this engine, so a base-owned reference is
    /// never theirs; every other actor answers from the record it was placed
    /// from. Memberships come from the faction runtime, seeded first so an
    /// actor nobody has asked about answers from its authored `SNAM` run.
    func crimeActor(_ key: ReferenceKey) -> CrimeActor {
        if let holder = actorValueHolder(for: key) {
            seedFactions(of: holder)
        }
        return CrimeActor(
            base: actorBaseKey(of: key),
            memberships: factions.runtime?.state(of: key) ?? ActorFactionState()
        )
    }

    /// The runtime identity of the NPC_ record `key` was placed from, which is
    /// what an `XOWN` actor link names.
    private func actorBaseKey(of key: ReferenceKey) -> ReferenceKey? {
        guard
            let base = streamer?.referenceEntry(key: key)?.placedActor?.base,
            let plugin = (worldData as? MagicDataProviding)?.magicItemPluginName,
            let resolved = crime.reporter?.runtime.factions
                .resolvedID(base, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }
}
