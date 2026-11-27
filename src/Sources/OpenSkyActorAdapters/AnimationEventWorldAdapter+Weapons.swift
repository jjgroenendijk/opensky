// The held weapon's draw, sheathe, swing, and attack loop sounds
// (docs/formats/item-records.md, WEAP).

public import OpenSkyActorPresentation
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkySessionInterface
import simd

extension AnimationEventWorldAdapter {
    public func playWeaponSound(
        _ event: WeaponSoundEvent, source: ReferenceKey, at position: SIMD3<Float>
    ) -> Bool {
        guard
            let director = game.gameSession?.soundDirector,
            let held = game.inventory.scriptItems.scriptEquippedWeapon(on: source, leftHand: event.isLeftHand),
            let weapon = held.flatMap({ game.combat.items?.weapon($0)?.details })
        else { return false }
        if event == .attackEnd {
            guard let loop = weapon.attackLoopSound else { return false }
            director.stopSound(formID: loop, source: source)
            return true
        }
        if case .swing = event, let loop = weapon.attackLoopSound {
            director.playSound(formID: loop, source: source, at: position)
        }
        guard let sound = event.sound(of: weapon) else { return false }
        return director.playSound(formID: sound, source: source, at: position)
    }
}
