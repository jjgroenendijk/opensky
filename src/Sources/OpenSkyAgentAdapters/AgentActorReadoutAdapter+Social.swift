// The terms behind an actor's hostility toward the player, for `state actors`.
// See docs/engine/hostility.md.

import OpenSkyAgentControl
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkySessionInterface

extension AgentActorReadoutAdapter {
    /// What the hostility rule read for `key`: the reaction, the aggression, a stored
    /// answer, and the factions of the actor and the player.
    func socialState(of key: ReferenceKey) -> AgentJSON {
        guard let profile = game.factions.profile(of: key) else { return .null }
        let reaction = game.factions.reaction(of: key, toward: .player)
        let player = game.factions.profile(of: .player)?.memberships.factions ?? []
        return [
            "reaction": reaction.map { .string("\($0)") } ?? .null,
            "aggression": .string("\(profile.aiData.aggression)"),
            "override": profile.hostilityOverride.map { .string("\($0)") } ?? .null,
            "factions": .array(profile.memberships.factions.map(Self.factionName)),
            "playerFactions": .array(player.map(Self.factionName))
        ]
    }

    private static func factionName(_ key: ReferenceKey) -> AgentJSON {
        .string("\(key)")
    }
}
