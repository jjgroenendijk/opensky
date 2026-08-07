// `ProjectileWorld` conformance (issue #196, roadmap item 15.5): the eleven
// answers the archery runtimes need from the session around them.
//
// Every one is a plain read off something that already exists — the camera's
// pose, the streamer's resident actors and its static broadphase, the ground
// contact's material, the actor-value runtime, the world audio engine, the
// inventory runtime, the world-state store, the locomotion bridge's graph.
// Nothing here invents an accounting of its own, which is what keeps the
// runtime's behaviour the same under test as it is in the app.
//
// Three answers are honest partial ones and are worth stating rather than
// papering over:
//
// * `projectileMaterial(at:)` reports the ground material under the player,
//   not the material of the surface the arrow struck. It is the same
//   limitation `meleeMaterial(at:)` has and the same reason: nothing in this
//   engine resolves a per-triangle material at an arbitrary world point yet
//   (issue #358 gave shapes a material; picking the struck triangle out of one
//   is a separate step).
// * `raiseArcheryEvent(_:)` can only reach the player's graph, because item
//   14.6 attached a behavior graph to the player and to nobody else.
// * A stuck arrow is spawned as the AMMO's own ground model through
//   `ReferenceSpawnState`, which is the one runtime-object channel this engine
//   has (item 12.1.3). Its transform is the impact point and the flight
//   direction; it is not attached to the *bone* of an actor it hit, so an actor
//   that walks away leaves the arrow where it landed. Attaching to a moving
//   host is `RigidAttachment`'s job and needs an actor-node transform channel
//   the spawn path does not have.

import AppKit
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

    func projectileMaterial(at position: SIMD3<Float>) -> FormID? {
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
