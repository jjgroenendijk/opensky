// The crime and faction half of the world-provider fake (issue #507), in its
// own file so `FakeWorldProviders` stays inside the type-length cap.
//
// Every answer is a stored value and every action is recorded rather than
// performed, which lets a panel test drive `World > Crime & Factions` with no
// renderer, no window and no game data.

@testable import OpenSkyCrime
@testable import OpenSkyEngine
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
    func modifySelectedBounty(by gold: Int32, violent: Bool) -> String {
        crimeFactions.bountyChanges.append((gold, violent))
        return "Moved the bounty by \(gold)."
    }

    @discardableResult
    func clearSelectedBounty() -> String {
        crimeFactions.clearCount += 1
        return "Cleared the bounty."
    }

    @discardableResult
    func checkGuardConfrontation() -> String {
        crimeFactions.guardChecks += 1
        return "Guard check."
    }

    @discardableResult
    func resistArrestWithSelectedFaction() -> String {
        crimeFactions.resistCount += 1
        return "Resisted arrest."
    }

    @discardableResult
    func selectSocialSubjectFromCrosshair() -> String {
        crimeFactions.crosshairPicks += 1
        return "Subject: crosshair."
    }

    @discardableResult
    func selectPlayerAsSocialSubject() -> String {
        crimeFactions.playerPicks += 1
        return "Subject: the player."
    }

    @discardableResult
    func joinSelectedFaction(rank: Int8) -> String {
        crimeFactions.joins.append(rank)
        return "Joined at rank \(rank)."
    }

    @discardableResult
    func leaveSelectedFaction() -> String {
        crimeFactions.leaveCount += 1
        return "Left."
    }

    @discardableResult
    func barterWithSocialSubject() -> String {
        crimeFactions.barterCount += 1
        return "Bartering."
    }
}
