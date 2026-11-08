import Foundation
public import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldInterface

/// What a guard does on seeing the player with a bounty.
nonisolated public enum CrimeResponse: Equatable, Sendable {
    /// Nothing: no bounty, or a faction that neither arrests nor attacks.
    case none
    /// Walk up and start the arrest conversation.
    case confront(bounty: Int32)
    /// Skip the conversation and fight.
    case attackOnSight(bounty: Int32)
}

/// The `CRVA` flags turned into a response for one bounty.
nonisolated public enum CrimeResponsePolicy: Sendable {
    /// `entry` is the faction's ledger row; nil owes nothing.
    public static func response(
        _ entry: CrimeLedgerEntry?,
        values: Faction.CrimeValues?,
        settings: CrimeSettings = .vanilla
    ) -> CrimeResponse {
        guard let entry, entry.gold > 0, let values else { return .none }
        // CK wiki "Creating a Custom Crime Faction": without Arrest, guards "always try
        // to kill the player on sight if there is a bounty".
        let pastLine = values.attackOnSight
            && settings.attacksOnSight(nonViolent: entry.nonViolentGold, violent: entry.violentGold)
        guard values.arrest, !pastLine else { return .attackOnSight(bounty: entry.gold) }
        return .confront(bounty: entry.gold)
    }
}

/// The crime term of the hostility derivation, over a snapshot of the player's
/// ledger. A guard is hostile when its faction attacks on sight at this bounty or
/// the player resisted arrest. A snapshot, because the derivation is nonisolated.
nonisolated public struct GuardCrimeHostility: CrimeHostilitySource, Equatable, Sendable {
    public let guardFaction: ReferenceKey?
    /// The ledger row per owed crime faction, which is all the term reads.
    public let bounties: [ReferenceKey: CrimeLedgerEntry]
    /// Each crime faction's `CRVA`.
    public let crimeValues: [ReferenceKey: Faction.CrimeValues]
    /// Crime factions the player resisted arrest with while owing them.
    public let resisted: Set<ReferenceKey>
    public let settings: CrimeSettings
    /// Per crime faction, the actors other than the player that struck one of its
    /// people first. Its guards fight them.
    public var actorCriminals: [ReferenceKey: Set<ReferenceKey>] = [:]

    public func crimeReaction(
        of observer: ActorSocialProfile,
        toward target: ActorSocialProfile
    ) -> ActorReaction? {
        if target.key != .player {
            guard
                let faction = GuardRecognition.policedFaction(
                    of: observer, guardFaction: guardFaction
                ),
                actorCriminals[faction]?.contains(target.key) == true
            else { return nil }
            return .enemy
        }
        guard
            let faction = GuardRecognition.policedFaction(
                of: observer, guardFaction: guardFaction
            ),
            let bounty = bounties[faction], bounty.gold > 0
        else { return nil }
        if resisted.contains(faction) {
            return .enemy
        }
        if
            case .attackOnSight = CrimeResponsePolicy.response(
                bounty, values: crimeValues[faction], settings: settings
            )
        {
            return .enemy
        }
        return nil
    }

    public init(
        guardFaction: ReferenceKey?,
        bounties: [ReferenceKey: CrimeLedgerEntry],
        crimeValues: [ReferenceKey: Faction.CrimeValues],
        resisted: Set<ReferenceKey>,
        settings: CrimeSettings = .vanilla
    ) {
        self.guardFaction = guardFaction
        self.bounties = bounties
        self.crimeValues = crimeValues
        self.resisted = resisted
        self.settings = settings
    }
}
