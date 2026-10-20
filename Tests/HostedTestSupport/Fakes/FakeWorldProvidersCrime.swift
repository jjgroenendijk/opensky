// The crime and faction part of the world-provider fake, split for the
// type-length cap. Answers are stored and actions recorded, so a panel test
// drives `World > Crime & Factions` without renderer or game data.

@testable import OpenSkyCrime
@testable import OpenSkyFormatsESM

/// The crime and faction half of the fake's stored state.
struct FakeCrimeFactionState {
    var snapshot = CrimeFactionControlSnapshot.unavailable
    var snapshotReads = 0
    var bountyFaction: ReferenceKey?
    var membershipFaction: ReferenceKey?
    var vendorOverride: ReferenceKey?
    /// Every bounty change the panel asked for, in order.
    var bountyChanges: [(gold: Int32, violent: Bool)] = []
    var clearCount = 0
    var guardChecks = 0
    var resistCount = 0
    var crosshairPicks = 0
    var playerPicks = 0
    /// Every rank a join asked for, in order.
    var joins: [Int8] = []
    var leaveCount = 0
    var barterCount = 0
}

/// The conformance is declared by `WorldControlProviders` on the class, so this
/// is a plain extension.
extension FakeWorldProviders {
    var crimeFactionSnapshot: CrimeFactionControlSnapshot {
        crimeFactions.snapshotReads += 1
        return crimeFactions.snapshot
    }

    var bountyFactionSelection: ReferenceKey? {
        get { crimeFactions.bountyFaction }
        set { crimeFactions.bountyFaction = newValue }
    }

    var membershipFactionSelection: ReferenceKey? {
        get { crimeFactions.membershipFaction }
        set { crimeFactions.membershipFaction = newValue }
    }

    var vendorOverrideSelection: ReferenceKey? {
        get { crimeFactions.vendorOverride }
        set { crimeFactions.vendorOverride = newValue }
    }

    @discardableResult
    func modifySelectedBounty(by gold: Int32, violent: Bool) -> CrimeFactionActionOutcome {
        crimeFactions.bountyChanges.append((gold, violent))
        return .bountyMoved(faction: "Whiterun", gold: gold, violent: violent, total: gold)
    }

    @discardableResult
    func clearSelectedBounty() -> CrimeFactionActionOutcome {
        crimeFactions.clearCount += 1
        return .bountyCleared(faction: "Whiterun", owed: 0)
    }

    @discardableResult
    func checkGuardConfrontation() -> CrimeFactionActionOutcome {
        crimeFactions.guardChecks += 1
        return .guardCheckNeedsSubject
    }

    @discardableResult
    func resistArrestWithSelectedFaction() -> CrimeFactionActionOutcome {
        crimeFactions.resistCount += 1
        return .resisted("Resisted arrest.")
    }

    @discardableResult
    func restockAllVendors() -> CrimeFactionActionOutcome {
        .restocked(chests: 0)
    }

    @discardableResult
    func serveJailSentence() -> CrimeFactionActionOutcome {
        .notInJail
    }

    @discardableResult
    func selectSocialSubjectFromCrosshair() -> CrimeFactionActionOutcome {
        crimeFactions.crosshairPicks += 1
        return .subjectSelected("crosshair")
    }

    @discardableResult
    func selectPlayerAsSocialSubject() -> CrimeFactionActionOutcome {
        crimeFactions.playerPicks += 1
        return .subjectSelected(nil)
    }

    @discardableResult
    func joinSelectedFaction(rank: Int8) -> CrimeFactionActionOutcome {
        crimeFactions.joins.append(rank)
        return .joined(actor: "The player", faction: "Whiterun", rank: rank, changed: true)
    }

    @discardableResult
    func leaveSelectedFaction() -> CrimeFactionActionOutcome {
        crimeFactions.leaveCount += 1
        return .left(actor: "The player", faction: "Whiterun", changed: true)
    }

    @discardableResult
    func barterWithSocialSubject() -> CrimeFactionActionOutcome {
        crimeFactions.barterCount += 1
        return .barter("Bartering.")
    }
}
