// Session wiring for crime (issue #504, roadmap item 21.5): builds the crime
// runtime over the provider's FACT and LCTN indexes, answers the four questions
// `CrimeWorld` asks about the running session, and routes the hooks — a take, a
// blow, a death — into the bounty ledger.
//
// AppKit stays in this controller satellite; the runtime, the reporter, the
// ownership resolver and the ledger component are all engine types that build
// into `openskycli` and are testable without a window.
//
// ## What is paid per take, and what is not
//
// `crimeOwner(of:)` runs once per take and once per container open, not per
// frame: it is two dictionary lookups and a resolve, and the answer is
// deliberately not cached, because a quest that hands the player a house key
// changes it and a cache would have to be invalidated by every membership
// write.
//
// The witness question is the perception pass's already-converged state, read
// rather than recomputed, so a take costs no raycast.

import AppKit

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
    /// Actors the player struck first this session, which is what makes the
    /// second blow of a fight not a second assault and the eventual death a
    /// murder rather than self-defence.
    ///
    /// Session state rather than a component: it answers "did this fight start
    /// with the player", and a reloaded save restarts every fight from what the
    /// records and the stored hostility say.
    var assaultedActors: Set<ReferenceKey> = []
    /// Cell the player was last seen in, so a trespass is noticed on arrival
    /// rather than once per frame for as long as they stay.
    var lastPlayerCell: CellSceneLocation?
    /// Human-readable result of the last crime the session recorded.
    var lastActionText = "No crime recorded yet."
}

extension GameViewController {
    /// Builds the crime runtime over the provider's FACT and LCTN indexes.
    ///
    /// Wired after `wireFactions` and `wireWorldItems`, because it hands the
    /// reporter to the world-item runtime those two already built and reads the
    /// same FACT store the hostility derivation does.
    func wireCrime(provider: any CellSceneProvider) {
        guard
            let factionStore = (provider as? FactionDataProviding)?.factionStore,
            let pluginName = (provider as? MagicDataProviding)?.magicItemPluginName
        else { return }
        let reporter = CrimeReporter(
            runtime: CrimeRuntime(store: worldState, factions: factionStore),
            world: self
        )
        crime.reporter = reporter
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

    /// Every faction the player owes something to or has offended.
    func resolvedCrimeFactions() -> [ResolvedFaction] {
        crime.reporter?.runtime.resolvedFactions() ?? []
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
            sourcePlugin: (streamerCellProvider as? MagicDataProviding)?.magicItemPluginName,
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
    /// hostile.
    ///
    /// Called from `reportScriptHit`, the one seam every landed blow passes
    /// through, which is why a sword and an arrow cannot disagree about what
    /// counts as a first strike. A blow struck by anybody but the player, a
    /// blow against the player, and a blow against an actor already angry are
    /// all no crime: "Self-defense against an unprovoked assault is legal and
    /// not considered a crime" (<https://en.uesp.net/wiki/Skyrim:Crime>).
    ///
    /// Only the *first* strike counts, which is what `assaultedActors` records:
    /// the second blow of the same fight is not a second crime, and the set is
    /// also what makes the eventual death a murder rather than self-defence.
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

    /// Records a death as murder when the player is the one who caused it.
    ///
    /// `assaultedActors` is the attribution, not a refinement of it. The
    /// zero-health sweep that notices a death knows only that health reached
    /// zero — not who emptied it — so charging every non-hostile death to the
    /// player would put a 1000-gold bounty on a bandit killing a guard, on fall
    /// damage, and on a script's `Kill`. The set holds exactly the actors this
    /// player struck first, which is the strongest claim this engine can make
    /// about who did it.
    ///
    /// That also gets the interesting half of the rule right: "If you kill an
    /// NPC or domestic animal after attacking them and making them hostile, you
    /// can be simultaneously guilty of both assault and murder"
    /// (<https://en.uesp.net/wiki/Skyrim:Crime>) — an actor the player
    /// assaulted is still a murder victim even though it died angry, while a
    /// bandit that attacked first is not. The stated deviation is the sentence
    /// after it: a one-hit kill charges assault as well as murder here, because
    /// the blow is reported before the sweep notices the death. Recorded in
    /// docs/engine/crime.md.
    func reportPlayerMurder(of victim: ReferenceKey, wasHostile: Bool) {
        guard
            victim != .player,
            crime.assaultedActors.contains(victim),
            let reporter = crime.reporter
        else { return }
        note(reporter.reportMurder(of: victim), as: "Murder")
    }

    /// Notices the player arriving somewhere an owner has not let them be.
    ///
    /// Called on every world tick and cheap when nothing moved: the cell the
    /// player stands in is compared against the last one seen and the ownership
    /// lookup runs only when it changed. One trespass per arrival, so standing
    /// in a shop does not accrue a bounty per frame.
    ///
    /// v1 records the trespass on arrival rather than after the warning the
    /// original gives — "you will receive one warning and be told to leave the
    /// area. If you linger and continue to trespass, you will receive a bounty
    /// after 30 seconds" (<https://en.uesp.net/wiki/Skyrim:Crime>). The warning
    /// is a guard line and a timer, which are issue #505's; recorded as a
    /// limitation in docs/engine/crime.md.
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
            key: key,
            base: actorBaseKey(of: key),
            memberships: factions.runtime?.state(of: key) ?? ActorFactionState()
        )
    }

    /// The runtime identity of the NPC_ record `key` was placed from, which is
    /// what an `XOWN` actor link names.
    private func actorBaseKey(of key: ReferenceKey) -> ReferenceKey? {
        guard
            let base = streamer?.referenceEntry(key: key)?.placedActor?.base,
            let plugin = (streamerCellProvider as? MagicDataProviding)?.magicItemPluginName,
            let resolved = crime.reporter?.runtime.factions
                .resolvedID(base, fromPlugin: plugin)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }
}
