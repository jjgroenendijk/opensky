// The crime and faction panel: what the readout shows and the controls it offers.
// Every value comes from the runtime the session itself consults, so the readout cannot
// disagree with the world. Every control reaches the call a script or the session
// already makes: a bounty through `CrimeRuntime.modifyCrimeGold` (`Faction.ModCrimeGold`),
// a membership through `joinFaction` (`Actor.AddToFaction`), and resisting through
// `resistArrest`.

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

/// What the faction panel reads from, and asks of, the crime coordinator.
protocol CrimeFactionPanelHost: AnyObject {
    var reporter: CrimeReporter? { get }
    /// One line each for the jail stay, the trespass watch, and the open reports.
    var panelStatusText: String { get }
    var lastCrimeText: String { get }
    var lastGuardText: String { get }
    var crimeTexts: CrimeTexts { get }
    func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey?
    func ownershipVerdict(on reference: ReferenceKey) -> OwnershipVerdict
    func factionName(_ faction: ReferenceKey) -> String
    func refreshGuardHostility()
    func resistArrest(with faction: ReferenceKey)
}

/// The panel part of `CrimeCoordinator`. It holds the world and its own selection,
/// and reaches the coordinator only through `CrimeFactionPanelHost`.
final class CrimeFactionPanel {
    weak var host: (any CrimeFactionPanelHost)?
    let world: any CrimeSessionWorld
    /// What the readout has selected. A nil selection falls back to the first
    /// option the snapshot offers, which is what the popups show.
    var bountyFaction: ReferenceKey?
    var membershipFaction: ReferenceKey?
    var vendorOverride: ReferenceKey?
    /// The actor the membership and vendor controls act on; nil is the player.
    var subject: ReferenceKey?
    private var lastAction = CrimeFactionActionOutcome.idle
    /// Built once per load order.
    private var options: CrimeFactionOptions?

    init(world: any CrimeSessionWorld) {
        self.world = world
    }

    var snapshot: CrimeFactionControlSnapshot {
        guard let host, let reporter = host.reporter, world.hasFactionData else {
            return .unavailable
        }
        let store = reporter.runtime.factions
        let options = factionOptions(store)
        let subject = subjectReadout(subject ?? .player, store: store)
        let override = vendorOverride
        var snapshot = CrimeFactionControlSnapshot(
            isAvailable: true,
            bounties: CrimeCore.bountyReadouts(
                reporter.runtime.ledger(), factions: store, texts: host.crimeTexts,
                settings: reporter.runtime.settings
            ),
            currentCrimeFaction: host.crimeFaction(in: world.currentCellLocation)
                .map { CrimeCore.factionOption($0, in: store) },
            ownership: world.targetOwnership(),
            ownerName: CrimeCore.ownerName(targetOwner(), in: store),
            stolenStacks: world.stolenPlayerStacks(),
            playerMemberships: membershipReadouts(of: .player, store: store),
            subject: subject,
            vendorFactions: options.vendors,
            vendorOverride: override,
            effectiveVendor: override.flatMap { world.vendor(faction: $0) } ?? subject.vendor,
            hour: world.hourOfDay,
            lastCrimeText: host.lastCrimeText,
            lastGuardText: host.lastGuardText,
            lastActionText: lastAction.text
        )
        snapshot.statusText = host.panelStatusText
        return snapshot
    }

    /// The selection, or the first crime faction, matching the popup.
    var effectiveBountyFaction: ReferenceKey? {
        guard let store = host?.reporter?.runtime.factions else { return nil }
        return bountyFaction ?? factionOptions(store).crime.first?.key
    }

    /// The selection, or the first faction, matching the popup.
    var effectiveMembershipFaction: ReferenceKey? {
        guard let store = host?.reporter?.runtime.factions else { return nil }
        return membershipFaction ?? factionOptions(store).all.first?.key
    }

    // MARK: - Bounty

    @discardableResult
    func modifySelectedBounty(by gold: Int32, violent: Bool) -> CrimeFactionActionOutcome {
        guard let host, let runtime = host.reporter?.runtime else { return note(.unavailable) }
        guard let faction = effectiveBountyFaction else { return note(.noCrimeFaction) }
        let total = runtime.modifyCrimeGold(by: gold, violent: violent, of: faction)
        host.refreshGuardHostility()
        return note(.bountyMoved(
            faction: host.factionName(faction), gold: gold, violent: violent, total: total
        ))
    }

    @discardableResult
    func clearSelectedBounty() -> CrimeFactionActionOutcome {
        guard let host, let runtime = host.reporter?.runtime else { return note(.unavailable) }
        guard let faction = effectiveBountyFaction else { return note(.noCrimeFaction) }
        let owed = runtime.clearCrimeGold(of: faction)
        host.refreshGuardHostility()
        return note(.bountyCleared(faction: host.factionName(faction), owed: owed))
    }

    @discardableResult
    func resistArrestWithSelectedFaction() -> CrimeFactionActionOutcome {
        guard let host, host.reporter != nil else { return note(.unavailable) }
        guard let faction = effectiveBountyFaction else { return note(.noCrimeFaction) }
        host.resistArrest(with: faction)
        return note(.resisted(host.lastGuardText))
    }

    // MARK: - Subject and memberships

    @discardableResult
    func joinSelectedFaction(rank: Int8) -> CrimeFactionActionOutcome {
        guard let host, world.hasFactionData else { return note(.unavailable) }
        guard let faction = effectiveMembershipFaction else { return note(.noFactions) }
        let key = subject ?? .player
        let changed = world.joinFaction(faction, actor: key, rank: rank)
        return note(.joined(
            actor: subjectName(key), faction: host.factionName(faction), rank: rank,
            changed: changed
        ))
    }

    @discardableResult
    func leaveSelectedFaction() -> CrimeFactionActionOutcome {
        guard let host, world.hasFactionData else { return note(.unavailable) }
        guard let faction = effectiveMembershipFaction else { return note(.noFactions) }
        let key = subject ?? .player
        return note(.left(
            actor: subjectName(key),
            faction: host.factionName(faction),
            changed: world.leaveFaction(faction, actor: key)
        ))
    }

    // MARK: - Private

    private func factionOptions(_ store: FactionStore) -> CrimeFactionOptions {
        if let options {
            return options
        }
        let built = CrimeCore.factionOptions(store)
        options = built
        return built
    }

    /// The owner the crosshair verdict was reached against, which may be the
    /// cell's rather than the reference's own.
    private func targetOwner() -> ReferenceOwner? {
        guard
            let interaction = world.crosshairInteraction,
            let entry = world.references?.referenceEntry(formID: interaction.reference)
        else { return nil }
        return host?.ownershipVerdict(on: entry.key).owner
    }

    private func membershipReadouts(
        of key: ReferenceKey,
        store: FactionStore
    ) -> [MembershipReadout] {
        (world.factionMemberships(of: key)?.memberships ?? []).map {
            MembershipReadout(
                faction: CrimeCore.factionOption($0.faction, in: store), rank: $0.rank
            )
        }
    }

    private func subjectReadout(_ key: ReferenceKey, store: FactionStore) -> SocialSubjectReadout {
        let profile = world.socialProfile(of: key)
        let policed = profile.flatMap {
            GuardRecognition.policedFaction(of: $0, guardFaction: store.guardFactionKey)
        }
        return SocialSubjectReadout(
            key: key,
            name: key == .player ? "the player" : world.actorName(key),
            memberships: membershipReadouts(of: key, store: store),
            towardPlayer: key == .player ? nil : profile.flatMap { world.reactionTerms(of: $0) },
            crimeFaction: profile?.crimeFaction.map { CrimeCore.factionOption($0, in: store) },
            policedFaction: policed.map { CrimeCore.factionOption($0, in: store) },
            vendor: world.vendor(of: key)
        )
    }

    private func subjectName(_ key: ReferenceKey) -> String {
        key == .player ? "The player" : world.actorName(key)
    }

    private func note(_ outcome: CrimeFactionActionOutcome) -> CrimeFactionActionOutcome {
        lastAction = outcome
        return outcome
    }
}
