// The trap natives that change how a reference moves: `SetMotionType` and `Reset`, and
// `Weapon.Fire` from a reference (docs/engine/traps.md).

import Foundation
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension EffectsWorldAdapter {
    /// The cell rebuild that the write starts makes the collision simulate or hold.
    /// A body made to hold keeps the pose it has now, not its last resting one.
    func setMotionType(_ motionType: ReferenceMotionType, of reference: ReferenceKey) -> Bool {
        guard let cell = game.streamer?.cellLocation(of: reference) else { return false }
        if motionType == .keyframed, let body = game.streamer?.dynamicBodies.body(for: reference) {
            let pose = PlacedReference.Placement(
                position: body.originPosition,
                rotation: MatrixMath.eulerAngles(of: body.orientation)
            )
            let current = game.scripts.bridge?.referenceState(for: reference)?.transform
            if current.map({ !Self.isSamePose(pose, as: $0.position, $0.rotation) }) ?? true {
                game.worldState.set(
                    ReferenceTransformOverride(
                        position: pose.position, rotation: pose.rotation,
                        scale: current?.scale ?? 1
                    ),
                    for: reference, in: cell
                )
            }
            game.streamer?.dynamicBodies.remove(reference)
        }
        game.worldState.set(motionType, for: reference, in: cell)
        return true
    }

    /// A body that never moved needs no transform write, which would rebuild the cell.
    private static func isSamePose(
        _ pose: PlacedReference.Placement, as position: SIMD3<Float>, _ rotation: SIMD3<Float>
    ) -> Bool {
        simd_distance(pose.position, position) < 0.01
            && simd_reduce_max(simd_abs(pose.rotation - rotation)) < 0.0001
    }

    /// Clears the moves and the motion type, or moves the object to `target`. Its
    /// inventory and other state stay. An actor is not reset.
    func resetReference(_ reference: ReferenceKey, to target: ReferenceKey?) -> Bool {
        guard
            let streamer = game.streamer,
            streamer.referenceEntry(key: reference)?.placedActor == nil
        else { return false }
        streamer.dynamicBodies.remove(reference)
        game.worldState.reset(.motionType, for: reference)
        guard
            let target,
            let destination = game.scripts.bridge?.referenceState(for: target)?.transform
        else {
            game.worldState.reset(.transform, for: reference)
            return true
        }
        let scale = game.scripts.bridge?.referenceState(for: reference)?.transform.scale ?? 1
        game.worldState.set(
            ReferenceTransformOverride(
                position: destination.position, rotation: destination.rotation, scale: scale
            ),
            for: reference, in: streamer.cellLocation(of: reference)
        )
        return true
    }

    /// The CK wiki "Fire - Weapon": a shot from a non-actor needs `akAmmo`, spends no
    /// ammunition, and leaves along the source's heading. Its damage is the weapon's
    /// plus the arrow's, with no skill or perk, and the weapon's enchantment applies.
    func fireWeapon(
        _ weapon: ReferenceKey, from source: ReferenceKey, ammunition: ReferenceKey?
    ) -> Bool {
        guard
            let items = game.combat.items, let bridge = game.scripts.bridge,
            let runtime = game.combat.archery,
            let weaponID = bridge.localFormID(of: weapon), let bow = items.weapon(weaponID),
            let ammunitionID = ammunition.flatMap(bridge.localFormID(of:)),
            let arrow = items.archeryAmmunition(ammunitionID),
            let shooter = shooter(at: source)
        else { return false }
        var payload = ArrowPayload(
            damage: ArcheryDamage.resolve(
                bowDamage: Float(bow.damage), arrowDamage: arrow.damage, skill: 0
            ),
            weapon: weaponID,
            ammunition: arrow.item,
            enchantment: game.magic.enchantmentProfile(of: weaponID)
        )
        payload.spendsAmmunition = false
        let shot = ProjectileShot(profile: arrow.profile, payload: .arrow(payload))
        return runtime.projectiles.fire(shot, from: shooter) != nil
    }

    private func shooter(at source: ReferenceKey) -> ProjectileShooter? {
        guard let transform = game.scripts.bridge?.referenceState(for: source)?.transform else {
            return nil
        }
        return ProjectileShooter(
            key: source,
            origin: transform.position,
            aim: ProjectileShooter.headingAim(zRotation: transform.rotation.z),
            isFirstPerson: false,
            location: game.streamer?.cellLocation(of: source)
        )
    }
}
