import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFactions
public import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyScripting
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `CrimeFactionsAdapter` reads from the session.
@MainActor
public protocol CrimeFactionsHost: AnyObject {
    var factions: any FactionPort { get }
}

/// Part of `CrimeWorldAdapter`, over its own narrow host.
public struct CrimeFactionsAdapter {
    public unowned let game: any CrimeFactionsHost
}

extension CrimeFactionsAdapter {
    public var hasFactionData: Bool {
        game.factions.runtime != nil
    }

    public func factionMemberships(of key: ReferenceKey) -> ActorFactionState? {
        game.factions.memberships(of: key)
    }

    public func socialProfile(of key: ReferenceKey) -> ActorSocialProfile? {
        game.factions.profile(of: key)
    }

    /// The same derivation the combat loop asks.
    public func reactionTerms(of observer: ActorSocialProfile) -> ReactionTermsReadout? {
        guard
            let player = game.factions.profile(of: .player),
            let derivation = game.factions.runtime?.derivation
        else { return nil }
        return ReactionTermsReadout(
            decision: derivation.decide(observer, toward: player),
            hostilityOverride: observer.hostilityOverride,
            crime: derivation.crime.crimeReaction(of: observer, toward: player),
            relationship: derivation.relationshipReaction(of: observer, toward: player),
            scriptedRank: derivation.scriptedRank(of: observer, toward: player),
            faction: derivation.factionReaction(of: observer, toward: player)
        )
    }

    public func joinFaction(_ faction: ReferenceKey, actor key: ReferenceKey, rank: Int8) -> Bool {
        game.factions.join(faction, actor: key, rank: rank)
    }

    public func leaveFaction(_ faction: ReferenceKey, actor key: ReferenceKey) -> Bool {
        game.factions.leave(faction, actor: key)
    }
}
