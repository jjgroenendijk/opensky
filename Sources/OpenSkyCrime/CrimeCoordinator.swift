// The shell of the crime domain: owns the bounty reporter, ownership, guard
// response, and the `World > Crime & Factions` panel state. It is the
// reporter's `CrimeWorld`. The rules live in `CrimeCore`, `CrimeRuntime`, and
// `GuardResponseState`. See docs/engine/coordinators.md and docs/engine/crime.md.

import OpenSkyConditions
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
    public var lastAction = CrimeFactionActionOutcome.idle
    /// Built once per load order.
    var options: CrimeFactionOptions?
}

/// Owns the crime runtimes and reads the world through `CrimeSessionWorld`.
/// Without a FACT index the reporter stays nil, and every take is honest.
@MainActor
public final class CrimeCoordinator {
    public private(set) var reporter: CrimeReporter? {
        didSet { conditionRevision &+= 1 }
    }

    /// The owner a script set on a reference with `SetActorOwner` or `SetFactionOwner`.
    /// `.some(nil)` means a script cleared the owner; nil means no script set one.
    public var scriptedOwner: ((ReferenceKey) -> ReferenceOwner??)? {
        didSet { conditionRevision &+= 1 }
    }

    /// Rises whenever a script sets or clears an owner, so the crime seam is rebuilt.
    public var scriptedOwnerRevision: (() -> UInt64)?
    var ownership: OwnershipResolver? {
        didSet { conditionRevision &+= 1 }
    }

    var crimeFactions: CrimeFactionResolver? {
        didSet { conditionRevision &+= 1 }
    }

    var pluginName: String? {
        didSet { conditionRevision &+= 1 }
    }

    /// Actors the player struck first. A later death counts as murder. Session
    /// state: a reloaded save restarts every fight.
    var assaultedActors: Set<ReferenceKey> = [] {
        didSet { conditionRevision &+= 1 }
    }

    /// Each murder's outcome, so a death reports once and `KILL` can read it.
    var murders: [ReferenceKey: CrimeOutcome] = [:] {
        didSet { conditionRevision &+= 1 }
    }

    /// Takes `ARRT` and `JAIL`, and is passed on to the reporter.
    public weak var storyEvents: (any StoryEventReporting)? {
        didSet { reporter?.storyEvents = storyEvents }
    }

    /// So a trespass is noticed on arrival rather than once per frame.
    var lastPlayerCell: CellSceneLocation?
    /// The warning and grace period of the current stay.
    public internal(set) var trespassWatch = TrespassWatch()
    /// Crimes charged while no guard knows yet. Session state, as `assaultedActors` is.
    public internal(set) var pendingReports: [PendingCrimeReport] = []
    /// The player's stay in jail, from the cell door to release or escape.
    public internal(set) var jailStay: JailStay?
    /// Blows between actors other than the player: who struck whom first.
    var actorFirstStrikes: Set<ActorStrike> = []
    /// Per crime faction, the actors whose guards fight them.
    public internal(set) var actorCriminals: [ReferenceKey: Set<ReferenceKey>] = [:]
    /// The player stands in a cell whose owner they may not use.
    public internal(set) var isPlayerTrespassing = false {
        didSet { conditionRevision &+= 1 }
    }

    /// Days served in the last jail sentence, for `GetDaysInJail`.
    var lastSentenceDays = 0 {
        didSet { conditionRevision &+= 1 }
    }

    public internal(set) var guards = GuardResponseState() {
        didSet { conditionRevision &+= 1 }
    }

    /// Rises on every change of the in-memory state the crime condition seam reads.
    private(set) var conditionRevision: UInt64 = 0
    let conditionCache = RevisionCache<CrimeConditionKey, CrimeConditionResolution>()
    /// Where each pursuing guard was last sent.
    var pursuitTargets: [ReferenceKey: SIMD3<Float>] = [:] {
        didSet { conditionRevision &+= 1 }
    }

    /// A guard walks toward the player or holds the arrest talk. Fast travel
    /// refuses with `sNoFastTravelAlarm` meanwhile.
    public var isPlayerPursued: Bool {
        !pursuitTargets.isEmpty || guards.active != nil
    }

    public internal(set) var lastCrime = CrimeNote.idle
    /// The crime names the bounty readout uses.
    public var crimeTexts = CrimeTexts.vanilla
    public internal(set) var lastGuard = GuardNote.idle
    public var panel = CrimeFactionPanelState()

    let world: any CrimeSessionWorld
    /// What crime asked of the app. The guard step returns and empties it.
    var pendingCommands: [CrimeCommand] = []

    public init(world: any CrimeSessionWorld) {
        self.world = world
    }

    /// Returns and empties what crime asked of the app. A command raised outside
    /// the guard step, such as by a hit report, also leaves with the next one.
    public func takeCommands() -> [CrimeCommand] {
        defer { pendingCommands = [] }
        return pendingCommands
    }

    /// `locations` is nil when the provider carries no LCTN index; then no
    /// place has a crime faction.
    public func wire(
        runtime: CrimeRuntime,
        locations: LocationStore?,
        pluginName: String
    ) {
        reporter = CrimeReporter(runtime: runtime, world: self)
        reporter?.storyEvents = storyEvents
        reporter?.onPlayerBounty = { [weak self] faction, gold in
            self?.showBountyNotice(gold: gold, added: true, faction: faction)
        }
        reporter?.onCrimeCharged = { [weak self] event, outcome, witnesses in
            self?.track(event, outcome: outcome, witnesses: witnesses)
        }
        reporter?.onCrimeRecorded = { [weak self] event, outcome in
            self?.count(event, outcome: outcome)
        }
        pendingReports = []
        jailStay = nil
        actorFirstStrikes = []
        actorCriminals = [:]
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
        guard aggressor == .player else {
            reportActorAssault(on: target, by: aggressor)
            return
        }
        guard
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
        guard
            victim != .player,
            assaultedActors.contains(victim),
            murders[victim] == nil,
            let reporter
        else { return }
        let outcome = reporter.reportMurder(of: victim)
        murders[victim] = outcome
        note(outcome, as: "Murder")
    }

    /// The `KILL` crime status: murder when the player struck first, reported
    /// when the murder cost gold.
    public func killStatus(of victim: ReferenceKey, by killer: ReferenceKey?) -> StoryKillStatus {
        guard killer == .player, assaultedActors.contains(victim) else { return .notMurder }
        return (murders[victim]?.gold ?? 0) > 0 ? .reportedMurder : .murder
    }

    /// Runs every tick with the real seconds since the last. The ownership lookup
    /// runs only when the cell changes; then a seen trespasser is warned and, after
    /// the grace period, charged (`TrespassWatch`).
    public func advanceTrespass(by seconds: Double = 0) {
        let location = world.currentCellLocation
        if lastPlayerCell != location {
            lastPlayerCell = location
            trespassWatch.enter(location)
            let flags = location.map(world.cellTrespassFlags(at:)) ?? CellTrespassFlags()
            isPlayerTrespassing = !flags.isPublicArea
                && cellOwner(at: location).map { !crimeActor(.player).mayUse($0) } == true
        }
        guard isPlayerTrespassing, let reporter else { return }
        let step = trespassWatch.step(
            seconds: seconds,
            seen: reporter.witnesses.isWitnessed(.player),
            offLimits: location.map { world.cellTrespassFlags(at: $0).isOffLimits } ?? false,
            settings: reporter.runtime.settings
        )
        switch step {
        case .none:
            break
        case let .warn(remaining):
            lastCrime = .trespassWarning(secondsLeft: Int(remaining.rounded(.up)))
            pendingCommands.append(.showNotice(crimeTexts.trespassWarning))
        case .charge:
            reportTrespass(in: location)
        }
    }

    public func reportTrespass(in location: CellSceneLocation?) {
        guard let reporter, let owner = cellOwner(at: location) else { return }
        guard !crimeActor(.player).mayUse(owner) else { return }
        note(reporter.reportTrespass(in: location, owner: owner), as: "Trespass")
    }

    /// A seen pick of a lock the player may not open. UESP "Skyrim:Crime" prices it
    /// like trespass, 5 gold.
    @discardableResult
    public func reportLockpicking(of lock: ReferenceKey) -> Int32 {
        guard let reporter else { return 0 }
        let verdict = reporter.verdict(on: lock)
        guard verdict.isTheft, let owner = verdict.owner else { return 0 }
        let outcome = reporter.reportTrespass(in: crimeCell(of: lock), owner: owner)
        note(outcome, as: "Lockpicking")
        return outcome.gold
    }

    func showBountyNotice(gold: Int32, added: Bool, faction: ReferenceKey) {
        guard gold > 0 else { return }
        pendingCommands.append(.showNotice(
            crimeTexts.bountyNotice(gold: gold, added: added, faction: factionName(faction))
        ))
    }

    private func note(_ outcome: CrimeOutcome, as label: String) {
        lastCrime = .recorded(outcome, label: label, faction: outcome.faction.map(factionName))
    }

    private func cellOwner(at location: CellSceneLocation?) -> ReferenceOwner? {
        guard let location, let ownership = world.cellOwnership(at: location) else { return nil }
        return self.ownership?.owner(of: ownership)
    }
}

extension CrimeCoordinator: CrimeWorld {
    /// A script-set owner first, then the reference's own `XOWN`, then the owner of the
    /// cell it stands in.
    public func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
        if let scripted = scriptedOwner?(key) {
            return scripted
        }
        guard let ownership else { return nil }
        let reference = world.references?.referenceEntry(key: key)?.placedReference
        let cell = crimeCell(of: key).flatMap { world.cellOwnership(at: $0) }
        return ownership.owner(
            reference: reference.flatMap(RecordOwnership.init(reference:)),
            cell: cell
        )
    }

    public func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey? {
        guard
            let cell,
            let link = world.cellLocationLink(at: cell),
            let resolvers = crimeFactions,
            let location = resolvers.locations.resolve(link.link, fromPlugin: link.plugin),
            let faction = resolvers.crimeFaction(of: location)
        else { return nil }
        return ReferenceKey(resolved: faction.id)
    }

    public func crimeCell(of key: ReferenceKey) -> CellSceneLocation? {
        world.references?.cellLocation(of: key)
    }

    public func crimeItemValue(of item: FormID) -> Int64 {
        world.itemValue(of: item)
    }

    /// The player has no `NPC_` base here, so a base-owned reference is never
    /// theirs. Memberships are seeded first, so an actor nobody asked about
    /// answers from its authored `SNAM` run.
    public func crimeActor(_ key: ReferenceKey) -> CrimeActor {
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
            let resolved = reporter?.runtime.factions.resolvedID(base, fromPlugin: pluginName)
        else { return nil }
        return ReferenceKey(resolved: resolved)
    }
}
