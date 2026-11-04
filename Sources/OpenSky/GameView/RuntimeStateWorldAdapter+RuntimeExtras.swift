// Engine state that has no world-state component of its own: the shout cooldown and a
// jail stay. A save keeps them on the player's script state, which the `SCRS` chunk
// already writes (docs/formats/opensky-save-world-chunks.md#scrs-script-state).

import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyScripting
import OpenSkyScriptingInterface

extension RuntimeStateWorldAdapter {
    private enum Extra {
        static let shoutCooldown = "engine:shoutCooldown"
        static let jailNonViolent = "engine:jailNonViolentGold"
        static let jailViolent = "engine:jailViolentGold"
        static let jailDays = "engine:jailDays"
        static let jailFaction = "engine:jailFaction"
        static let jailMarker = "engine:jailMarker"
        static let jailBelongings = "engine:jailBelongings"
        static func jailOutfit(_ index: Int) -> String {
            "engine:jailOutfit\(index)"
        }
    }

    /// Writes the state just before the snapshot is taken.
    func storeRuntimeExtras() {
        guard let bridge = game.scripts.bridge else { return }
        let cooldown = game.magic.shoutMachine.cooldown
        let stay = game.crime.jailStay
        let outfit = stay?.outfit.compactMap(bridge.referenceKey(forFormID:)) ?? []
        bridge.updateScriptedState(of: .player) { state in
            state.setValue(Extra.shoutCooldown, cooldown > 0 ? cooldown : nil)
            state.setValue(Extra.jailNonViolent, stay.map { Float($0.nonViolentGold) })
            state.setValue(Extra.jailViolent, stay.map { Float($0.violentGold) })
            state.setValue(Extra.jailDays, stay.map { Float($0.sentenceDays) })
            state.setForm(Extra.jailFaction, stay?.faction)
            state.setForm(Extra.jailMarker, stay?.exteriorMarker)
            state.setForm(Extra.jailBelongings, stay?.belongings)
            for index in 0 ..< max(outfit.count, Self.maximumOutfitPieces) {
                state.setForm(Extra.jailOutfit(index), index < outfit.count ? outfit[index] : nil)
            }
        }
    }

    /// Reads the state back after the world state of a save is restored.
    func restoreRuntimeExtras() {
        guard let bridge = game.scripts.bridge else { return }
        let state = bridge.scriptedState(of: .player)
        game.magic.restoreShoutCooldown(state.value(Extra.shoutCooldown) ?? 0)
        guard
            let faction = state.form(Extra.jailFaction),
            let marker = state.form(Extra.jailMarker)
        else {
            game.crime.restoreJailStay(nil)
            return
        }
        let outfit = (0 ..< Self.maximumOutfitPieces).compactMap {
            state.form(Extra.jailOutfit($0)).flatMap(bridge.localFormID(of:))
        }
        game.crime.restoreJailStay(JailStay(
            faction: faction,
            nonViolentGold: Int32(state.value(Extra.jailNonViolent) ?? 0),
            violentGold: Int32(state.value(Extra.jailViolent) ?? 0),
            sentenceDays: Int(state.value(Extra.jailDays) ?? 0),
            exteriorMarker: marker,
            belongings: state.form(Extra.jailBelongings),
            outfit: outfit,
            arrestedIn: nil
        ))
    }

    /// A jail outfit has a few pieces; the slots past it are cleared on each save.
    private static let maximumOutfitPieces = 8
}
