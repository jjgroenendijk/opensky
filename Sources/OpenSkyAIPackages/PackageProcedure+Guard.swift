// The Guard procedure: warn an intruder near the restricted area a few times, then
// attack (<https://ck.uesp.net/wiki/Guard_(Procedure)>).

import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

nonisolated extension PackageProcedureMachine {
    /// `iGuardWarnings`: the most warnings a guard gives before it attacks.
    static let guardWarnings = 2
    /// `FAITrespassWarningTimer`: seconds between two warnings.
    static let trespassWarningSeconds: Float = 5

    /// True while the guard has warned an intruder that is still in its warn radius.
    public var isWarning: Bool {
        kind == .guardArea && warnings > 0
    }

    /// `near` is the immediate attack radius and `far` the warn radius, both measured
    /// from the edge of the restricted area.
    mutating func guardArea(intruder: SIMD3<Float>) -> [PackageProcedureCommand] {
        guard state == .waiting, let watched = setup.watched else { return [] }
        let distance = max(0, simd_distance(intruder, center) - radius)
        let warnRadius = max(setup.far, setup.near)
        if setup.near > 0, distance <= setup.near {
            return attack(watched)
        }
        guard distance <= warnRadius else {
            guard warnings > 0 else { return [] }
            warnings = 0
            warnCooldown = 0
            return act(.standDown)
        }
        guard warnCooldown <= 0 else { return [] }
        if warnings >= Self.guardWarnings {
            return attack(watched)
        }
        warnings += 1
        warnCooldown = Self.trespassWarningSeconds
        return act(.warn(watched, level: warnings))
    }

    private mutating func attack(_ intruder: ReferenceKey) -> [PackageProcedureCommand] {
        warnings = 0
        warnCooldown = 0
        return act(.attack(intruder, startsCombat: true))
    }
}
