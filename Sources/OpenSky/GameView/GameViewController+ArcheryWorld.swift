// `ProjectileWorld` conformance: the answers the archery runtimes need, each a
// plain read off an existing session system. Known partial answers:
// - `projectileMaterial()` uses the ground material under the player.
// - `raiseArcheryEvent(_:)` reaches only the player's behavior graph.
// - A stuck arrow is a spawned AMMO model at the impact point. It does not
//   follow the bone of the actor it hit.

import AppKit
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldState
import simd

extension GameViewController: ProjectileWorld {
    var projectileShooter: ProjectileShooter {
        guard let renderer else {
            return ProjectileShooter(
                key: .player, origin: SIMD3(), aim: SIMD3(1, 0, 0),
                isFirstPerson: true, location: nil
            )
        }
        return ProjectileShooter(
            key: .player,
            origin: renderer.freeFlyCamera.position,
            aim: renderer.freeFlyCamera.forward,
            isFirstPerson: renderer.movementMode != .thirdPerson,
            location: streamer?.currentCellLocation
        )
    }

    func projectileTargets() -> [MeleeTarget] {
        meleeTargets()
    }

    func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit? {
        guard let streamer else { return nil }
        return ShapeSweeper.firstHit(
            query: query,
            shapes: streamer.staticCollisionCandidates(overlapping: query.bounds)
        )
    }

    func projectileMaterial() -> FormID? {
        renderer?.walkController.groundMaterial
    }

    @discardableResult
    func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        applyMeleeDamage(amount, to: target)
    }

    func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        playMeleeImpact(impact, at: position)
    }

    @discardableResult
    func consumeArrow(_ ammunition: FormID) -> Bool {
        guard let runtime = worldItems.runtime else { return false }
        do {
            try runtime.inventory.remove(ammunition, count: 1, from: runtime.player)
            return true
        } catch {
            // An empty quiver is ordinary play, not a fault: the shot simply
            // does not happen and the panel's readout says the arrow count is
            // zero.
            return false
        }
    }

    @discardableResult
    func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey? {
        let key = worldState.allocateGeneratedKey()
        worldState.set(
            ReferenceSpawnState(
                base: arrow.base,
                location: arrow.location,
                placement: PlacedReference.Placement(
                    position: arrow.position, rotation: arrow.rotation
                ),
                count: 1
            ),
            for: key,
            in: arrow.location
        )
        archery.stuckKeys.insert(key)
        return key
    }

    func removeStuckProjectile(_ key: ReferenceKey) {
        guard archery.stuckKeys.remove(key) != nil else { return }
        // `reset` rather than a deletion component: the object exists only
        // because the store says so, so dropping its whole delta is what makes
        // it gone and leaves nothing behind in the next save. Exactly what
        // `WorldItemRuntime.removeFromWorld` does for a spawned object.
        worldState.reset(key)
    }

    func residentProjectileCells() -> Set<CellSceneLocation> {
        guard let streamer else { return [] }
        if let interior = streamer.interiorScene?.location {
            return [interior]
        }
        return Set(streamer.composition.cells.values.compactMap(\.location))
    }

    @discardableResult
    func raiseArcheryEvent(_ name: String) -> Bool {
        raiseCombatEvent(name, on: nil)
    }

    func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String) {
        writeCombatVariable(value, named: name)
    }
}
