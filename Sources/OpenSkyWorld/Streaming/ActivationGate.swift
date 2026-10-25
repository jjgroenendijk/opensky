// The check every use-key activation passes before it publishes. The lock runtime
// answers it; a refused press raises a refusal event and nothing else.
// See docs/engine/locks.md.

import OpenSkyGameData
import OpenSkyWorldInterface

@MainActor
public struct ActivationGateSeam {
    /// One check per step, asked in step order. The first refusal wins.
    private var checks: [(
        step: ActivationGateStep,
        check: (InteractionTarget) -> ActivationRefusal?
    )] = []
    /// Asked after the gate lets a press through. True means the player's perk
    /// choices took the press over, so the target's own action does not run.
    public var perkChoices: ((InteractionTarget) -> Bool)?
    /// Fires for each refused press. The HUD, audio, and the lockpicking menu listen.
    public let refusals = FrameSchedule<ActivationRefusalStep, ActivationRefusalEvent>()

    public init() {}

    /// A second check in one step is a wiring bug and traps.
    public mutating func register(
        _ step: ActivationGateStep,
        _ check: @escaping (InteractionTarget) -> ActivationRefusal?
    ) {
        precondition(!checks.contains { $0.step == step }, "gate step \(step) registered twice")
        let index = checks.firstIndex { $0.step.rawValue > step.rawValue } ?? checks.count
        checks.insert((step, check), at: index)
    }

    /// The first refusal in step order, or nil to let the press through.
    public func refusal(for target: InteractionTarget) -> ActivationRefusal? {
        for entry in checks {
            if let refusal = entry.check(target) {
                return refusal
            }
        }
        return nil
    }
}
