// Forced explosions: detonate an `EXPL` in front of the
// camera, throw `DEBR` pieces, spawn a `HAZD`, and read the live hazards.

import OpenSkyPhysics

nonisolated public struct ExplosionControlSnapshot: Equatable, Sendable {
    public let reports: [ExplosionReport]
    public let detonationTotal: Int
    public let debrisCount: Int
    public let skippedPlacements: Int
    public let hazards: [TrapHazardRow]

    public init(
        reports: [ExplosionReport],
        detonationTotal: Int,
        debrisCount: Int,
        skippedPlacements: Int,
        hazards: [TrapHazardRow]
    ) {
        self.reports = reports
        self.detonationTotal = detonationTotal
        self.debrisCount = debrisCount
        self.skippedPlacements = skippedPlacements
        self.hazards = hazards
    }
}
