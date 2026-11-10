// What the last lock action did, as a value. The readout turns it into a line, so
// the rules never build sentences (docs/engine/coordinators.md).

import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
import OpenSkyWorldState

nonisolated extension LockTexts {
    public func text(for notice: LockNotice) -> String {
        switch notice {
        case .requiresKey: requiresKey
        case .outOfLockpicks: outOfLockpicks
        case .pursued: pursued
        }
    }

    func text(for outcome: LockActionOutcome) -> String {
        switch outcome {
        case .idle: "No lock action yet."
        case .noRuntime: "No item runtime."
        case .noSelection: "No lock selected."
        case let .noLock(name): "\(name) has no lock."
        case let .blockedByPerk(name): "A perk blocks activating \(name)."
        case let .unlockedWithKey(name): "Unlocked \(name) with its key."
        case let .refused(name, difficulty): "\(name) is locked (\(self.name(of: difficulty)))."
        case let .lockChanged(name, locked): "\(locked ? "Locked" : "Unlocked") \(name)."
        case .picking, .pickRefused, .notice, .pickBroke, .stoppedPicking, .picked,
             .caughtPicking:
            pickingText(for: outcome)
        }
    }

    private func pickingText(for outcome: LockActionOutcome) -> String {
        switch outcome {
        case let .picking(name, difficulty): "Picking \(name) (\(self.name(of: difficulty)))."
        case let .pickRefused(refusal, name): Self.text(for: refusal, name: name)
        case let .notice(notice): text(for: notice)
        case .pickBroke: "A lockpick broke."
        case .stoppedPicking: "Stopped picking."
        case let .picked(name): "Picked \(name ?? "the lock")."
        case let .caughtPicking(bounty): "Seen picking an owned lock; bounty \(bounty)."
        default: ""
        }
    }

    static func text(for refusal: LockpickingRefusal, name: String) -> String {
        switch refusal {
        case .noLockpicks: "\(name) is locked and you have no lockpicks."
        case .requiresKey: "\(name) requires a key."
        case .notLocked: "\(name) is not locked."
        case .noRuntime, .unknownReference: "\(name) cannot be picked."
        }
    }
}
