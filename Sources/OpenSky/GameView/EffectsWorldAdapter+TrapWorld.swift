// The trap natives' world: `PlaceAtMe` spawns hazards, detonates explosions, or places objects,
// impulses push simulated bodies, and pushback knocks actors back (docs/engine/traps.md).

import Foundation
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension EffectsWorldAdapter: PapyrusTrapWorldBridge {
    func placeAtMe(_ base: ReferenceKey, at anchor: ReferenceKey, count: Int) -> ReferenceKey? {
        guard let position = trapPosition(of: anchor) else { return nil }
        if let spec = game.hazardWorld.store?.spec(for: base) {
            var last: ReferenceKey?
            for _ in 0 ..< max(1, count) {
                let key = nextHazardKey()
                game.hazards.spawn(HazardPlacement(id: key, spec: spec, position: position))
                last = key
            }
            return last
        }
        guard let spec = explosions.spec(for: base) else { return spawn(
            base,
            at: anchor,
            count: count
        ) }
        for _ in 0 ..< max(1, count) {
            explosions.detonate(spec, at: position, cause: .script)
        }
        // An explosion leaves no reference a script can hold.
        return nil
    }

    /// Papyrus impulses are in Havok units; the bodies simulate in game units.
    func applyImpulse(_ impulse: SIMD3<Float>, to reference: ReferenceKey) -> Bool {
        guard let body = game.streamer?.dynamicBodies.body(for: reference) else { return false }
        game.streamer?.dynamicBodies.applyImpulse(
            impulse * NIFCollisionModel.havokToEngineScale, at: body.position, to: reference
        )
        return true
    }

    /// The player and an NPC slide on their capsules. The game also ragdolls an NPC
    /// that `PushActorAway` hits; OpenSky does not.
    func pushActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey,
        along direction: SIMD3<Float>?, speed: Float
    ) -> Bool {
        guard speed != 0, speed.isFinite, let feet = trapPosition(of: actor) else { return false }
        let away = direction ?? trapPosition(of: source).map { feet - $0 } ?? .zero
        let flat = SIMD3(away.x, away.y, 0)
        guard simd_length(flat) > 0 else { return false }
        let velocity = simd_normalize(flat) * speed
        guard actor == .player else {
            return game.streamer?.knockActor(actor, velocity: velocity) ?? false
        }
        game.gameSession?.walkController.knock(velocity)
        return true
    }

    func staggerActor(_ actor: ReferenceKey, magnitude: Float) -> Bool {
        game.magicWorld.staggerActor(actor, magnitude: magnitude)
    }

    /// Any other base becomes `count` spawned references, and the last one is answered.
    private func spawn(_ base: ReferenceKey, at anchor: ReferenceKey, count: Int) -> ReferenceKey? {
        guard let bridge = game.scripts.bridge else { return nil }
        var last: ReferenceKey?
        for _ in 0 ..< max(1, count) {
            last = bridge.spawnReference(of: base, at: anchor) ?? last
        }
        return last
    }

    /// Where a reference stands now: the player's feet, a moved NPC's capsule, or its
    /// placement.
    func trapPosition(of reference: ReferenceKey) -> SIMD3<Float>? {
        if reference == .player {
            return game.gameSession?.walkController.feetPosition
        }
        return game.streamer?.npcTransform(for: reference)?.position
            ?? game.scripts.bridge?.referenceState(for: reference)?.transform.position
    }
}
