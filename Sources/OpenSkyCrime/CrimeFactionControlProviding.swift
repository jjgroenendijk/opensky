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
import OpenSkyActorsInterface
import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// One faction a popup offers, named the way the readout names it.
nonisolated public struct FactionOption: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String

    public init(key: ReferenceKey, name: String) {
        self.key = key
        self.name = name
    }
}

/// One row of the player's bounty ledger.
nonisolated public struct BountyReadout: Equatable, Sendable {
    public let faction: FactionOption
    public let nonViolentGold: Int32
    public let violentGold: Int32
    public let counts: CrimeCounts
    /// What a guard of this faction does on seeing the player at this bounty.
    public let response: CrimeResponse

    public var gold: Int32 {
        Int32(clamping: Int64(nonViolentGold) + Int64(violentGold))
    }

    public init(
        faction: FactionOption,
        nonViolentGold: Int32,
        violentGold: Int32,
        counts: CrimeCounts,
        response: CrimeResponse
    ) {
        self.faction = faction
        self.nonViolentGold = nonViolentGold
        self.violentGold = violentGold
        self.counts = counts
        self.response = response
    }
}

/// One membership, resolved to a name.
nonisolated public struct MembershipReadout: Equatable, Sendable {
    public let faction: FactionOption
    public let rank: Int8

    public init(faction: FactionOption, rank: Int8) {
        self.faction = faction
        self.rank = rank
    }
}

/// Every term of the hostility precedence list for one ordered pair, so a
/// reader sees which one answered and what the others would have said.
nonisolated public struct ReactionTermsReadout: Equatable, Sendable {
    public let decision: HostilityDecision
    /// The stored `ActorCombatState` answer, which beats every record term.
    public let hostilityOverride: ActorHostility?
    public let crime: ActorReaction?
    /// The reaction the relationship rank collapses to, scripted or authored.
    public let relationship: ActorReaction?
    /// The scripted rank behind `relationship`, when a script set one.
    public let scriptedRank: Int8?
    /// The most hostile interfaction relation between the two membership lists.
    public let faction: ActorReaction?

    public init(
        decision: HostilityDecision,
        hostilityOverride: ActorHostility?,
        crime: ActorReaction?,
        relationship: ActorReaction?,
        scriptedRank: Int8?,
        faction: ActorReaction?
    ) {
        self.decision = decision
        self.hostilityOverride = hostilityOverride
        self.crime = crime
        self.relationship = relationship
        self.scriptedRank = scriptedRank
        self.faction = faction
    }
}

/// The actor the membership and vendor controls act on.
nonisolated public struct SocialSubjectReadout: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    public let memberships: [MembershipReadout]
    /// What this actor makes of the player; nil for the player itself.
    public let towardPlayer: ReactionTermsReadout?
    /// The `CRIF` crime faction this actor reports to.
    public let crimeFaction: FactionOption?
    /// The crime faction this actor polices, when it is a guard.
    public let policedFaction: FactionOption?
    /// The vendor role its memberships give it, before any panel override.
    public let vendor: Vendor?

    public init(
        key: ReferenceKey,
        name: String,
        memberships: [MembershipReadout],
        towardPlayer: ReactionTermsReadout?,
        crimeFaction: FactionOption?,
        policedFaction: FactionOption?,
        vendor: Vendor?
    ) {
        self.key = key
        self.name = name
        self.memberships = memberships
        self.towardPlayer = towardPlayer
        self.crimeFaction = crimeFaction
        self.policedFaction = policedFaction
        self.vendor = vendor
    }
}

/// One observation of the crime and faction runtimes.
nonisolated public struct CrimeFactionControlSnapshot: Equatable, Sendable {
    /// False when no crime or faction runtime is attached — no game data, or a
    /// demo scene. The panel then says so rather than showing an empty ledger
    /// that looks like an honest player.
    public let isAvailable: Bool
    public let bounties: [BountyReadout]
    /// The crime faction answering for the cell the player stands in.
    public let currentCrimeFaction: FactionOption?
    /// What taking the reference under the crosshair would be, and whose it is.
    public let ownership: ReferenceOwnershipReadout?
    public let ownerName: String?
    /// The player's stolen stacks, one row per form.
    public let stolenStacks: [ItemStackReadout]
    /// Factions that track crime, which is what a bounty can be written to.
    public let crimeFactions: [FactionOption]
    public let selectedCrimeFaction: ReferenceKey?
    public let playerMemberships: [MembershipReadout]
    public let subject: SocialSubjectReadout
    /// Every faction the load order carries, for the membership controls.
    public let factions: [FactionOption]
    public let selectedFaction: ReferenceKey?
    /// Every vendor faction, for the merchant override.
    public let vendorFactions: [FactionOption]
    public let vendorOverride: ReferenceKey?
    /// The vendor the next barter uses: the override when one is chosen, the
    /// subject's own role otherwise.
    public let effectiveVendor: Vendor?
    /// The game hour the vendor's window is judged at, or nil with no clock.
    public let hour: Float?
    public let lastCrimeText: String
    public let lastGuardText: String
    public let lastActionText: String

    /// The reading with no runtime attached.
    public static let unavailable = CrimeFactionControlSnapshot(
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

    public init(
        isAvailable: Bool,
        bounties: [BountyReadout],
        currentCrimeFaction: FactionOption?,
        ownership: ReferenceOwnershipReadout?,
        ownerName: String?,
        stolenStacks: [ItemStackReadout],
        crimeFactions: [FactionOption],
        selectedCrimeFaction: ReferenceKey?,
        playerMemberships: [MembershipReadout],
        subject: SocialSubjectReadout,
        factions: [FactionOption],
        selectedFaction: ReferenceKey?,
        vendorFactions: [FactionOption],
        vendorOverride: ReferenceKey?,
        effectiveVendor: Vendor?,
        hour: Float?,
        lastCrimeText: String,
        lastGuardText: String,
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.bounties = bounties
        self.currentCrimeFaction = currentCrimeFaction
        self.ownership = ownership
        self.ownerName = ownerName
        self.stolenStacks = stolenStacks
        self.crimeFactions = crimeFactions
        self.selectedCrimeFaction = selectedCrimeFaction
        self.playerMemberships = playerMemberships
        self.subject = subject
        self.factions = factions
        self.selectedFaction = selectedFaction
        self.vendorFactions = vendorFactions
        self.vendorOverride = vendorOverride
        self.effectiveVendor = effectiveVendor
        self.hour = hour
        self.lastCrimeText = lastCrimeText
        self.lastGuardText = lastGuardText
        self.lastActionText = lastActionText
    }
}

@MainActor
public protocol CrimeFactionControlProviding: AnyObject {
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
