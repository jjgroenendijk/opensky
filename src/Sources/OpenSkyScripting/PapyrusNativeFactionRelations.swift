// `Faction` natives that change how two factions react to each other
// (<https://ck.uesp.net/wiki/Faction_Script>). The reaction is kept in the faction's
// script state, so a save keeps it, and the hostility derivation reads it over XNAM.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

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
        // `SetReaction(Faction akOther, int aiNewValue)` sets one side only. The wiki says 3
        // makes friends, so the value is read as an `XNAM` combat reaction code.
        scriptState("Faction", "SetReaction", into: &registry) { call, bridge, faction in
            guard
                let other = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let code = integer(call, at: 1), code >= 0,
                let reaction = ActorReaction(Faction.CombatReaction(rawValue: UInt32(code)))
            else { return failure(call, "SetReaction needs a faction and a reaction from 0 to 3") }
            bridge.setFactionReaction(reaction, of: faction, toward: other)
            return .returned(.none)
        }
        // `SetPlayerEnemy(bool abIsEnemy = true)`: enemies of the player's faction, or
        // neutral to it again.
        scriptState("Faction", "SetPlayerEnemy", into: &registry) { call, bridge, faction in
            let reaction: ActorReaction = boolean(call, at: 0, default: true) ? .enemy : .neutral
            bridge.setFactionReaction(reaction, of: faction, toward: playerFaction)
            bridge.setFactionReaction(reaction, of: playerFaction, toward: faction)
            return .returned(.none)
        }
        // `SendAssaultAlarm()` "finds a nearby member of this faction" and has it react as
        // if the player assaulted it. The member is the resident actor nearest the player.
        scriptState("Faction", "SendAssaultAlarm", into: &registry) { call, bridge, faction in
            guard let members = residentMembers(of: faction, bridge) else {
                return failure(call, "SendAssaultAlarm needs a session with a faction runtime")
            }
            guard let witness = members.first else { return .returned(.none) }
            guard bridge.sendAssaultAlarm(witness: witness, criminal: bridge.playerKey) != nil
            else { return failure(call, "SendAssaultAlarm needs a session with a crime runtime") }
            return .returned(.none)
        }
    }

    /// Resident actors in `faction`, nearest the player first; nil without a faction runtime.
    private static func residentMembers(
        of faction: ReferenceKey, _ bridge: PapyrusWorldStateBridge
    ) -> [ReferenceKey]? {
        let actors = (bridge.references?.residentEntries() ?? []).compactMap { entry in
            entry.placedActor == nil ? nil : entry.key
        }
        var members: [ReferenceKey] = []
        for actor in actors {
            guard let isMember = bridge.isInFaction(actor, faction: faction) else { return nil }
            if isMember {
                members.append(actor)
            }
        }
        let centre = position(of: bridge.playerKey, bridge)
        let distance = { (key: ReferenceKey) -> Float in
            guard let centre, let here = position(of: key, bridge) else { return .infinity }
            return simd_distance(centre, here)
        }
        return members.sorted { (distance($0), $0) < (distance($1), $1) }
    }
}
