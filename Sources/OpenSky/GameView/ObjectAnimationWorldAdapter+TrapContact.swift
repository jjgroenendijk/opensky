// Trap contact: each frame, the moving bones of a scripted trap meet the resident
// actors, and the trap's scripts get `OnTrapHitStart`, `OnTrapHit`, and `OnTrapHitStop`.
// The contact rule lives in `TrapContactTracker`. See docs/engine/traps.md.

import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyObjectAnimation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension ObjectAnimationWorldAdapter {
    func advanceTrapContact(_ delta: Float) {
        guard let runtime = game.scripts.runtime, let streamer = game.streamer else { return }
        var resident: Set<ReferenceKey> = []
        let targets = trapTargets()
        for reference in objects.runningReferences {
            guard
                let entry = streamer.referenceEntry(formID: FormID(reference)),
                runtime.handlesTrapHits(on: entry.key),
                let local = objects.bonePositions(of: reference),
                let state = game.scripts.bridge?.referenceState(for: entry.key)
            else { continue }
            resident.insert(entry.key)
            let toWorld = MatrixMath.placement(
                position: state.transform.position, rotation: state.transform.rotation,
                scale: entry.placedReference?.scale ?? 1
            )
            let positions = local.map { point in
                let world = toWorld * SIMD4(point, 1)
                return SIMD3(world.x, world.y, world.z)
            }
            let points = trapContact.points(of: entry.key, positions: positions, delta: delta)
            let events = trapContact.step(
                trap: entry.key, points: points, targets: targets, delta: delta
            )
            for event in events {
                switch event {
                case let .hit(trap, target, point, initial):
                    runtime.queueTrapHit(PapyrusTrapHit(
                        target: target, velocity: point.velocity, position: point.position,
                        initial: initial
                    ), on: trap)
                case let .stop(trap, target):
                    runtime.queueTrapHitStop(target: target, on: trap)
                }
            }
        }
        trapContact.retain(resident)
    }

    private func trapTargets() -> [TrapContactTarget] {
        var targets = game.actorWorld.combatActors().filter { !$0.isDead }.map {
            TrapContactTarget(
                key: $0.key, feet: $0.feet, radius: $0.capsule.radius, height: $0.capsule.height
            )
        }
        if let feet = game.gameSession?.locomotion.status.feetPosition {
            let capsule = PlayerCapsule.standard
            targets.append(TrapContactTarget(
                key: .player, feet: feet, radius: capsule.radius, height: capsule.height
            ))
        }
        return targets
    }
}
