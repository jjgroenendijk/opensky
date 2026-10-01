// The pure rules behind the Player & Locomotion and First person readouts.

import Foundation
import OpenSkyBehavior

/// Readout rows built from plain values.
nonisolated public enum PlayerCore {
    /// Every gameplay key with its live state, so the panel lists each binding.
    public static func bindings(
        run: Bool,
        sprint: Bool,
        sneak: Bool,
        airborne: Bool
    ) -> [LocomotionBindingSnapshot] {
        [
            LocomotionBindingSnapshot(label: "Run", key: "Shift (hold)", isActive: run),
            LocomotionBindingSnapshot(label: "Sprint", key: "Option (hold)", isActive: sprint),
            LocomotionBindingSnapshot(label: "Sneak", key: "C (toggle)", isActive: sneak),
            LocomotionBindingSnapshot(label: "Jump", key: "Space", isActive: airborne)
        ]
    }

    /// A name the graph does not declare gets a nil value, so a spelling
    /// mismatch shows on the panel.
    public static func variables(of graph: BehaviorGraphInstance?) -> [LocomotionVariableSnapshot] {
        let names = LocomotionGraphNames.variables + [LocomotionGraphNames.isFirstPerson]
        return names.map { name in
            LocomotionVariableSnapshot(
                name: name, value: graph?.variable(named: name).map(describe)
            )
        }
    }

    public static func describe(_ value: BehaviorVariableValue) -> String {
        switch value {
        case let .bool(flag): flag ? "true" : "false"
        case let .int(number): String(number)
        case let .real(number): String(format: "%.3f", number)
        case let .quad(vector):
            String(format: "%.3f, %.3f, %.3f, %.3f", vector.x, vector.y, vector.z, vector.w)
        }
    }

    /// Worn pieces the first-person projection dropped for having no MOD4 or
    /// MOD5, counted off the assembly's own skips.
    public static func droppedPieceCount(of rig: PlayerFirstPersonRig?) -> Int {
        guard let rig else { return 0 }
        return rig.assembly.skips.count {
            guard case let .appearance(skip) = $0.subject else { return false }
            return skip.reason == .noFirstPersonModel
        }
    }
}
