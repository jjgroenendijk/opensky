// The sound the player makes, as detection hears it: actions and spell casting.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import simd

extension AIDetectionSenseAdapter {
    var sound: Sound {
        Sound(game: game)
    }

    struct Sound {
        let game: any AIDetectionSenseHost

        /// A swing sounds at its weapon's `VNAM` level and a cast at its first
        /// effect's casting sound level, for as long as it lasts.
        func playerActionSound() -> Float {
            guard let settings = game.perception.runtime?.settings else { return 0 }
            var loudest: Float = 0
            if let melee = game.combat.melee, melee.state.attackPhase != .idle {
                let level = melee.weapon.weapon
                    .flatMap { game.combat.items?.weapon($0)?.details.detectionSoundLevel }
                    .flatMap(DetectionSoundLevel.init(rawValue:)) ?? .normal
                loudest = max(loudest, settings.actionSound(for: level))
            }
            if let caster = game.magic.caster {
                for hand in SpellHand.allCases where caster.phase(of: hand).isCasting {
                    let spell = caster.state(of: hand).spell
                    let level = castingSoundLevel(spell, caster: caster)
                    loudest = max(
                        loudest,
                        settings.actionSound(for: level) * castingSoundFactor(spell, caster: caster)
                    )
                }
            }
            return loudest
        }

        /// Quiet Casting sets Mod Spell Casting Sound Event to 0, which silences the cast.
        func castingSoundFactor(
            _ spell: ReferenceKey?,
            caster: any CasterRuntimePort
        ) -> Float {
            let spells = caster.spellbook.spells
            let resolved = spell.flatMap { spells.spell(key: $0) }
            var seams = ConditionContext()
            seams.spellEvaluation = SpellEvaluationResolution(spell: resolved)
            let factor = game.perks.modified(
                1,
                at: .modSpellCastingSoundEvent,
                on: .player,
                subjects: { _ in
                    PerkEvaluationSubjects(owner: .player)
                        .binding(.spell, to: resolved.map(spells.conditionSubject(of:)))
                },
                seams: seams
            )
            return factor.isFinite ? max(0, factor) : 1
        }

        func castingSoundLevel(
            _ spell: ReferenceKey?, caster: any CasterRuntimePort
        ) -> DetectionSoundLevel {
            guard
                let spell,
                let record = caster.spellbook.record(spell),
                let raw = record.effects.lazy
                    .compactMap({ $0.effect?.effect.data?.castingSoundLevel })
                    .first
            else { return .normal }
            return DetectionSoundLevel(rawValue: raw) ?? .normal
        }
    }
}
