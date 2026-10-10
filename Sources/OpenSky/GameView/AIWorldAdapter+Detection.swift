// The detection inputs that come from other systems: Sneak skills from actor
// values, armour weight from equipment, muffle and invisibility from the actor
// values magic effects move, the action sound of a swing or a cast, and the
// light the renderer shades the player with. See docs/engine/detection.md.

import OpenSkyActors
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering
import simd

extension AIWorldAdapter {
    /// `Sneak`, `Invisibility`, and `Movement Noise Mult` in the vanilla table.
    private static let sneakIndex: Int32 = 15
    private static let invisibilityIndex: Int32 = 54
    private static let movementNoiseMultIndex: Int32 = 92
    /// Point lights the sample sums; the nearest ones carry nearly all the light.
    private static let sampledPointLights = 8

    func sneakSkill(of actor: ReferenceKey) -> Float {
        actorValue(Self.sneakIndex, of: actor) ?? DetectionTargetTraits.startingSkill
    }

    func playerDetectionTraits(at feet: SIMD3<Float>, eyeHeight: Float) -> DetectionTargetTraits {
        DetectionTargetTraits(
            equippedWeight: playerArmourWeight(),
            lightLevel: lightLevel(at: feet + SIMD3(0, 0, eyeHeight * 0.5)),
            muffle: actorValue(Self.movementNoiseMultIndex, of: .player) ?? 0,
            actionSound: playerActionSound(),
            sneakSkill: sneakSkill(of: .player),
            isInvisible: (actorValue(Self.invisibilityIndex, of: .player) ?? 0) > 0
        )
    }

    private func actorValue(_ index: Int32, of actor: ReferenceKey) -> Float? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: actor)
        else { return nil }
        return runtime.value(at: index, on: holder)
    }

    /// UESP counts armour weight only; a carried sword makes no movement noise.
    private func playerArmourWeight() -> Float {
        guard let equipment = game.inventory.equipment, let items = game.combat.items else {
            return 0
        }
        return equipment.equipped(on: InventoryHolder.player).reduce(0) { total, item in
            guard let definition = items.definition(item), definition.family == .armor else {
                return total
            }
            return total + max(0, definition.weight)
        }
    }

    /// A swing sounds at its weapon's `VNAM` level and a cast at its first
    /// effect's casting sound level, for as long as it lasts.
    private func playerActionSound() -> Float {
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
                let level = castingSoundLevel(caster.state(of: hand).spell, caster: caster)
                loudest = max(loudest, settings.actionSound(for: level))
            }
        }
        return loudest
    }

    private func castingSoundLevel(
        _ spell: ReferenceKey?, caster: CasterRuntime
    ) -> DetectionSoundLevel {
        guard
            let spell,
            let record = caster.spellbook.record(spell),
            let raw = record.effects.lazy.compactMap({ $0.effect?.effect.data?.castingSoundLevel })
                .first
        else { return .normal }
        return DetectionSoundLevel(rawValue: raw) ?? .normal
    }

    /// The same ambient, directional, and point light the scene pass shades with.
    private func lightLevel(at position: SIMD3<Float>) -> Float {
        guard let renderer = game.renderer, let settings = game.perception.runtime?.settings else {
            return 1
        }
        let scene = renderer.scene
        let interior = scene.lighting
        let weather = interior == nil ? renderer.currentResolvedWeather : nil
        let sample = DetectionLightSample(
            ambient: weather?.ambientColor ?? interior?.ambientColor
                ?? renderer.camera.ambientColor,
            directional: weather?.sunlightColor ?? interior?.directionalColor
                ?? renderer.camera.sunColor,
            pointLights: scene.nearestPointLights(to: position, limit: Self.sampledPointLights)
                .map {
                    DetectionPointLight(
                        position: $0.position, radius: $0.radius, colour: $0.color,
                        falloffExponent: $0.falloffExponent
                    )
                }
        )
        return sample.level(at: position, fullLuminance: settings.fullLightLuminance.value)
    }
}
