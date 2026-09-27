// Main-app crime and faction inspection seam (issue #507, roadmap item 21.8):
// what the `World > Crime & Factions` panel is written against, so the panel
// stays independent of `GameViewController` while reaching the same engine
// calls the runtime uses — `CrimeRuntime.modifyCrimeGold`, `FactionRuntime.join`,
// `HostilityDerivation.decide`, `VendorResolver`.
//
// One snapshot value, for the reason `ProgressionControlSnapshot` is one: a
// readout has to be a pure function of a single engine observation, and a
// bounty, the guard reaction it provokes and the membership that reaction is
// measured against move together.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One faction a popup offers, named the way the readout names it.
nonisolated struct FactionOption: Equatable, Sendable {
    let key: ReferenceKey
    let name: String
}

/// One row of the player's bounty ledger.
nonisolated struct BountyReadout: Equatable, Sendable {
    let faction: FactionOption
    let nonViolentGold: Int32
    let violentGold: Int32
    let counts: CrimeCounts
    /// What a guard of this faction does on seeing the player at this bounty.
    let response: CrimeResponse

    var gold: Int32 {
        Int32(clamping: Int64(nonViolentGold) + Int64(violentGold))
    }
}

/// One membership, resolved to a name.
nonisolated struct MembershipReadout: Equatable, Sendable {
    let faction: FactionOption
    let rank: Int8
}

/// Every term of the hostility precedence list for one ordered pair, so a
/// reader sees which one answered and what the others would have said.
nonisolated struct ReactionTermsReadout: Equatable, Sendable {
    let decision: HostilityDecision
    /// The stored `ActorCombatState` answer, which beats every record term.
    let hostilityOverride: ActorHostility?
    let crime: ActorReaction?
    /// The reaction the relationship rank collapses to, scripted or authored.
    let relationship: ActorReaction?
    /// The scripted rank behind `relationship`, when a script set one.
    let scriptedRank: Int8?
    /// The most hostile interfaction relation between the two membership lists.
    let faction: ActorReaction?
}

/// The actor the membership and vendor controls act on.
nonisolated struct SocialSubjectReadout: Equatable, Sendable {
    let key: ReferenceKey
    let name: String
    let memberships: [MembershipReadout]
    /// What this actor makes of the player; nil for the player itself.
    let towardPlayer: ReactionTermsReadout?
    /// The `CRIF` crime faction this actor reports to.
    let crimeFaction: FactionOption?
    /// The crime faction this actor polices, when it is a guard.
    let policedFaction: FactionOption?
    /// The vendor role its memberships give it, before any panel override.
    let vendor: Vendor?
}

/// One observation of the crime and faction runtimes.
nonisolated struct CrimeFactionControlSnapshot: Equatable, Sendable {
    /// False when no crime or faction runtime is attached — no game data, or a
    /// demo scene. The panel then says so rather than showing an empty ledger
    /// that looks like an honest player.
    let isAvailable: Bool
    let bounties: [BountyReadout]
    /// The crime faction answering for the cell the player stands in.
    let currentCrimeFaction: FactionOption?
    /// What taking the reference under the crosshair would be, and whose it is.
    let ownership: ReferenceOwnershipReadout?
    let ownerName: String?
    /// The player's stolen stacks, one row per form.
    let stolenStacks: [ItemStackReadout]
    /// Factions that track crime, which is what a bounty can be written to.
    let crimeFactions: [FactionOption]
    let selectedCrimeFaction: ReferenceKey?
    let playerMemberships: [MembershipReadout]
    let subject: SocialSubjectReadout
    /// Every faction the load order carries, for the membership controls.
    let factions: [FactionOption]
    let selectedFaction: ReferenceKey?
    /// Every vendor faction, for the merchant override.
    let vendorFactions: [FactionOption]
    let vendorOverride: ReferenceKey?
    /// The vendor the next barter uses: the override when one is chosen, the
    /// subject's own role otherwise.
    let effectiveVendor: Vendor?
    /// The game hour the vendor's window is judged at, or nil with no clock.
    let hour: Float?
    let lastCrimeText: String
    let lastGuardText: String
    let lastActionText: String

    /// The reading with no runtime attached.
    static let unavailable = CrimeFactionControlSnapshot(
        isAvailable: false,
        bounties: [],
        currentCrimeFaction: nil,
        ownership: nil,
        ownerName: nil,
        stolenStacks: [],
        crimeFactions: [],
        selectedCrimeFaction: nil,
        playerMemberships: [],
        subject: SocialSubjectReadout(
            key: .player, name: "the player", memberships: [], towardPlayer: nil,
            crimeFaction: nil, policedFaction: nil, vendor: nil
        ),
        factions: [],
        selectedFaction: nil,
        vendorFactions: [],
        vendorOverride: nil,
        effectiveVendor: nil,
        hour: nil,
        lastCrimeText: "No crime recorded yet.",
        lastGuardText: "No guard has acted yet.",
        lastActionText: "Crime and factions unavailable: no game data loaded."
    )
}

@MainActor
protocol CrimeFactionControlProviding: AnyObject {
    var crimeFactionSnapshot: CrimeFactionControlSnapshot { get }

    /// The crime faction the bounty controls write to.
    var bountyFactionSelection: ReferenceKey? { get set }

    /// The faction the membership controls join and leave.
    var membershipFactionSelection: ReferenceKey? { get set }

    /// A vendor faction the next barter trades under in place of the one the
    /// subject's memberships resolve, or nil to use the resolved one.
    var vendorOverrideSelection: ReferenceKey? { get set }

    /// Moves one half of the player's bounty with the selected faction, which
    /// is `Faction.ModCrimeGold`.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func modifySelectedBounty(by gold: Int32, violent: Bool) -> String

    /// Clears both halves of the bounty with the selected faction.
    @discardableResult
    func clearSelectedBounty() -> String

    /// Asks what the subject would do about the player's bounty right now if
    /// it is a guard, and runs one guard-response tick when a world is live.
    @discardableResult
    func checkGuardConfrontation() -> String

    /// Refuses arrest with the selected faction, turning its guards hostile.
    @discardableResult
    func resistArrestWithSelectedFaction() -> String

    /// Makes the actor under the crosshair the subject.
    @discardableResult
    func selectSocialSubjectFromCrosshair() -> String

    /// Makes the player the subject again.
    @discardableResult
    func selectPlayerAsSocialSubject() -> String

    /// Puts the subject in the selected faction at `rank`, or moves it there.
    @discardableResult
    func joinSelectedFaction(rank: Int8) -> String

    /// Takes the subject out of the selected faction.
    @discardableResult
    func leaveSelectedFaction() -> String

    /// Opens the barter menu against the subject under the effective vendor.
    @discardableResult
    func barterWithSocialSubject() -> String
}
