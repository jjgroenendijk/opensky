// The casting hands' sounds: a hand's sound plays at its caster and a loop runs until
// the cue that stops it. See docs/engine/spellcasting.md.

import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyWorld
import simd

extension MagicWorldAdapter {
    func castingSound(_ sound: FormID, caster: ReferenceKey, starts: Bool) {
        guard let director = game.gameSession?.soundDirector else { return }
        guard starts else {
            director.stopSound(formID: sound, source: caster)
            return
        }
        let combat = game.combat
        let feet = caster == .player
            ? combat.meleeAttacker.feet : combat.combatActor(key: caster)?.feet
        guard let feet else { return }
        director.playSound(formID: sound, source: caster, at: feet)
    }
}
