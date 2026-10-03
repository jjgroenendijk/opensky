// Panel seam of World > Effects > Explosions: detonate an `EXPL` in front of the
// camera, throw `DEBR` pieces, spawn a `HAZD`, and read the live hazards.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

public protocol ExplosionControlProviding: AnyObject {
    var explosionNames: [String] { get }
    var debrisNames: [String] { get }
    var hazardNames: [String] { get }
    @discardableResult
    func detonateExplosion(named name: String) -> Bool
    @discardableResult
    func throwDebris(named name: String) -> Int
    @discardableResult
    func spawnHazard(named name: String) -> Bool
    func clearExplosions()
    var explosionSnapshot: ExplosionControlSnapshot { get }
}

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

/// The session parts the explosion controls need beyond the combat coordinator.
@MainActor
public protocol ExplosionControlWorld: AnyObject {
    /// A point on the camera's view line, where a debug detonation lands.
    var effectsViewPoint: SIMD3<Float>? { get }
    var hazardNames: [String] { get }
    func spawnHazard(named name: String, at position: SIMD3<Float>) -> Bool
    var hazardRows: [TrapHazardRow] { get }
}

public protocol ExplosionControlForwarding: ExplosionControlProviding {
    var combat: CombatCoordinator { get }
    var explosionControlWorld: any ExplosionControlWorld { get }
}

extension ExplosionControlForwarding {
    public var explosionNames: [String] {
        combat.explosions.records.explosions.records.compactMap(\.record.editorID).sorted()
    }

    public var debrisNames: [String] {
        combat.explosions.records.debris.records.compactMap(\.record.editorID).sorted()
    }

    public var hazardNames: [String] {
        explosionControlWorld.hazardNames
    }

    public func detonateExplosion(named name: String) -> Bool {
        let runtime = combat.explosions
        guard
            let point = explosionControlWorld.effectsViewPoint,
            let resolved = runtime.records.explosions.record(editorID: name),
            let spec = runtime.spec(for: ReferenceKey(resolved: resolved.id))
        else { return false }
        runtime.detonate(spec, at: point, cause: .debug)
        return true
    }

    public func throwDebris(named name: String) -> Int {
        let runtime = combat.explosions
        guard
            let point = explosionControlWorld.effectsViewPoint,
            let resolved = runtime.records.debris.record(editorID: name)
        else { return 0 }
        return runtime.throwDebris(
            ReferenceKey(resolved: resolved.id), at: point, force: DebrisSelection.panelForce
        )
    }

    public func spawnHazard(named name: String) -> Bool {
        guard let point = explosionControlWorld.effectsViewPoint else { return false }
        return explosionControlWorld.spawnHazard(named: name, at: point)
    }

    public func clearExplosions() {
        combat.explosions.clear()
    }

    public var explosionSnapshot: ExplosionControlSnapshot {
        let runtime = combat.explosions
        return ExplosionControlSnapshot(
            reports: runtime.reports,
            detonationTotal: runtime.detonationTotal,
            debrisCount: runtime.debris.count,
            skippedPlacements: runtime.skippedPlacements,
            hazards: explosionControlWorld.hazardRows
        )
    }
}
