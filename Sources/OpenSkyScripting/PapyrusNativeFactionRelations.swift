// `Faction` natives that change how two factions react to each other
// (<https://ck.uesp.net/wiki/Faction_Script>). The reaction is kept in the faction's
// script state, so a save keeps it, and the hostility derivation reads it over XNAM.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `PlayerFaction`, Skyrim.esm `000DB1`, which `SetPlayerEnemy` pairs with.
    static let playerFaction = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x000DB1)

    public static func installFactionRelations(into registry: inout PapyrusNativeRegistry) {
        // `SetEnemy(Faction akOther, bool abSelfIsNeutralToOther = false,
        // bool abOtherIsNeutralToSelf = false)`: a true flag makes that side neutral.
        // `SetAlly` has the same shape, and a true flag makes that side a friend.
        let pairs: [String: (base: ActorReaction, softened: ActorReaction)] = [
            "SetEnemy": (.enemy, .neutral),
            "SetAlly": (.ally, .friend)
        ]
        for (name, pair) in pairs.sorted(by: { $0.key < $1.key }) {
            scriptState("Faction", name, into: &registry) { call, bridge, faction in
                guard let other = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:))
                else { return failure(call, "\(name) needs a faction") }
                let mine = boolean(call, at: 1, default: false) ? pair.softened : pair.base
                let theirs = boolean(call, at: 2, default: false) ? pair.softened : pair.base
                bridge.setFactionReaction(mine, of: faction, toward: other)
                bridge.setFactionReaction(theirs, of: other, toward: faction)
                return .returned(.none)
            }
        }
        // `SetPlayerEnemy(bool abIsEnemy = true)`: enemies of the player's faction, or
        // neutral to it again.
        scriptState("Faction", "SetPlayerEnemy", into: &registry) { call, bridge, faction in
            let reaction: ActorReaction = boolean(call, at: 0, default: true) ? .enemy : .neutral
            bridge.setFactionReaction(reaction, of: faction, toward: playerFaction)
            bridge.setFactionReaction(reaction, of: playerFaction, toward: faction)
            return .returned(.none)
        }
    }
}
