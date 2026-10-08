// The trap natives' world: `PlaceAtMe` spawns hazards and detonates explosions,
// impulses push simulated bodies, and pushback knocks the player back
// (docs/engine/traps.md).

import Foundation
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyMagic
import OpenSkyPhysics
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
        guard let spec = explosions.spec(for: base) else { return nil }
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

    /// Only the player is pushed: NPC movement has no outside velocity yet.
    func pushActor(
        _ actor: ReferenceKey, awayFrom source: ReferenceKey,
        along direction: SIMD3<Float>?, speed: Float
    ) -> Bool {
        guard actor == .player, speed > 0, let renderer = game.renderer else { return false }
        let feet = renderer.walkController.feetPosition
        let away = direction ?? trapPosition(of: source).map { feet - $0 } ?? .zero
        let flat = SIMD3(away.x, away.y, 0)
        guard simd_length(flat) > 0 else { return false }
        renderer.walkController.knock(simd_normalize(flat) * speed)
        return true
    }

    private func trapPosition(of reference: ReferenceKey) -> SIMD3<Float>? {
        if reference == .player {
            return game.renderer?.walkController.feetPosition
        }
        return game.scripts.bridge?.referenceState(for: reference)?.transform.position
    }
}
