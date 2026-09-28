// Text for the `World > Crime & Factions` readouts (issue #507), kept out of the
// AppKit sections so the wording is unit-testable and every section reads one
// snapshot the same way.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum CrimeFactionReadout: Sendable {
    // MARK: - Bounty

    /// The ledger, the place the player stands in, and what the last crime and
    /// the last guard did.
    public static func bountyText(for snapshot: CrimeFactionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastActionText }
        let total = snapshot.bounties.reduce(Int64(0)) { $0 + Int64($1.gold) }
        var lines = ["Bounty: \(total) gold with \(snapshot.bounties.count) faction(s)"]
        for bounty in snapshot.bounties {
            lines.append("  \(bounty.faction.name): \(bounty.gold) (non-violent "
                + "\(bounty.nonViolentGold), violent \(bounty.violentGold)) · "
                + "\(countsText(bounty.counts)) · guards \(responseText(bounty.response))")
        }
        lines.append("Crime faction here: \(snapshot.currentCrimeFaction?.name ?? "none")")
        lines.append("Last crime: \(snapshot.lastCrimeText)")
        lines.append("Last guard: \(snapshot.lastGuardText)")
        lines.append(snapshot.lastActionText)
        return lines.joined(separator: "\n")
    }

    public static func responseText(_ response: CrimeResponse) -> String {
        switch response {
        case .none: "ignore"
        case .confront: "confront"
        case .attackOnSight: "attack on sight"
        }
    }

    private static func countsText(_ counts: CrimeCounts) -> String {
        let parts = CrimeKind.allCases.compactMap { kind -> String? in
            counts[kind] > 0 ? "\(kind.rawValue) \(counts[kind])" : nil
        }
        return parts.isEmpty ? "no crimes counted" : parts.joined(separator: ", ")
    }

    // MARK: - Theft

    /// The crosshair verdict and the stolen copies the player carries.
    public static func theftText(for snapshot: CrimeFactionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastActionText }
        var lines: [String] = []
        if let ownership = snapshot.ownership {
            lines.append("Target: \(ownership.name) · \(ownership.reference)")
            lines.append("Owner: \(snapshot.ownerName ?? "none")")
            lines.append(ownership.isTheft
                ? "Taking it is theft · bounty if witnessed \(ownership.bounty) gold"
                : "Taking it is not theft")
        } else {
            lines.append("Target: none — point the walk-mode crosshair at a reference.")
        }
        let stolen = snapshot.stolenStacks.reduce(Int64(0)) { $0 + Int64($1.count) }
        lines.append("Stolen in the player's inventory: \(stolen) item(s)")
        for stack in snapshot.stolenStacks {
            lines.append("  \(stack.name) × \(stack.count) · \(stack.item)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Memberships

    /// Both membership lists, what the subject makes of the player and why,
    /// and whether it is a guard.
    public static func membershipText(for snapshot: CrimeFactionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastActionText }
        let subject = snapshot.subject
        var lines = membershipLines("Player", snapshot.playerMemberships)
        if subject.key != .player {
            lines += membershipLines("\(subject.name) · \(subject.key)", subject.memberships)
        }
        if let terms = subject.towardPlayer {
            lines += reactionLines(terms)
        }
        lines.append("Crime faction (CRIF): \(subject.crimeFaction?.name ?? "none")")
        lines.append("Guard: " + (subject.policedFaction.map { "polices \($0.name)" } ?? "no"))
        return lines.joined(separator: "\n")
    }

    private static func membershipLines(
        _ title: String,
        _ memberships: [MembershipReadout]
    ) -> [String] {
        [title + " — \(memberships.count) membership(s):"]
            + memberships.map { "  \($0.faction.name) rank \($0.rank)" }
    }

    /// The precedence list top to bottom, marking the term that answered.
    public static func reactionLines(_ terms: ReactionTermsReadout) -> [String] {
        let decision = terms.decision
        return [
            "Toward the player: \(name(decision.hostility)), reaction "
                + "\(name(decision.reaction)) from \(decision.source.displayName)",
            "  override: " + (terms.hostilityOverride.map(name) ?? "none"),
            "  crime: " + (terms.crime.map(name) ?? "no opinion"),
            "  relationship: " + (terms.relationship.map(name) ?? "none")
                + (terms.scriptedRank.map { " (scripted rank \($0))" } ?? ""),
            "  faction relation: " + (terms.faction.map(name) ?? "none")
        ]
    }

    public static func name(_ reaction: ActorReaction) -> String {
        switch reaction {
        case .ally: "ally"
        case .friend: "friend"
        case .neutral: "neutral"
        case .enemy: "enemy"
        }
    }

    public static func name(_ hostility: ActorHostility) -> String {
        hostility == .hostile ? "hostile" : "not hostile"
    }

    // MARK: - Vendor

    /// The subject's resolved vendor role, the override over it, and whether
    /// it trades at this hour.
    public static func vendorText(for snapshot: CrimeFactionControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastActionText }
        let resolved = snapshot.subject.vendor?.factionName ?? "not a merchant"
        var lines = ["\(snapshot.subject.name): \(resolved)"]
        if let override = snapshot.vendorOverride {
            let name = snapshot.vendorFactions.first { $0.key == override }?.name
            lines.append("Override: \(name ?? override.description)")
        }
        guard let vendor = snapshot.effectiveVendor else {
            return lines.joined(separator: "\n")
        }
        lines.append("Chest: " + (vendor.merchantChest.map(\.description) ?? "own inventory"))
        lines.append(hoursText(vendor, hour: snapshot.hour))
        let list = vendor.listKeywords.map { "\($0.count) keyword(s)" } ?? "no list"
        lines.append("Buy/sell list: \(list)\(vendor.negatesList ? ", negated" : "")")
        lines.append("Fence: \(vendor.buysStolen ? "yes" : "no")")
        return lines.joined(separator: "\n")
    }

    private static func hoursText(_ vendor: Vendor, hour: Float?) -> String {
        guard let hours = vendor.hours else { return "Hours: always" }
        let window = "Hours: \(hours.start)-\(hours.end)"
        guard let hour else { return window }
        return window + (vendor.isOpen(atHour: hour) ? " · open now" : " · closed now")
    }
}
