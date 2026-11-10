// Forced explosions: detonate an `EXPL` in front of the
// camera, throw `DEBR` pieces, spawn a `HAZD`, and read the live hazards.

public import OpenSkyCombatInterface
public import OpenSkyPhysics

nonisolated struct ExplosionControlSnapshot: Equatable, Sendable {
    let reports: [ExplosionReport]
    let detonationTotal: Int
    let debrisCount: Int
    let skippedPlacements: Int
    let hazards: [TrapHazardRow]
}
