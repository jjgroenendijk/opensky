// The one place anything asks "what is this quest's state right now?" (issue
// #182), mirroring `GlobalResolution`.
//
// Resolution order is fixed and total: a runtime state recorded in this session
// wins, the plugin baseline is the answer otherwise, and nil means the FormID
// names no quest the store knows. Consumers never reach past this into
// `WorldStateStore`, which is what lets a condition evaluated on a build thread
// read quest state from a snapshot just as easily as the main actor reads it
// from the live store.
//
// Documented in docs/engine/quest-state.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct QuestResolution: Sendable {
    private let defaults: QuestStore
    private let overrides: [ReferenceKey: QuestRuntimeState]

    public static let empty = QuestResolution(defaults: .empty, overrides: [:])

    public init(defaults: QuestStore?, overrides: [ReferenceKey: QuestRuntimeState] = [:]) {
        self.defaults = defaults ?? .empty
        self.overrides = overrides
    }

    /// Resolution over a snapshot's quest components, for a consumer running
    /// off the main actor where the live store is unreachable.
    public init(defaults: QuestStore?, snapshot: WorldStateSnapshot) {
        var overrides: [ReferenceKey: QuestRuntimeState] = [:]
        for entry in snapshot.entries {
            guard let state = entry.delta.component(QuestRuntimeState.self) else { continue }
            overrides[entry.key] = state
        }
        self.init(defaults: defaults, overrides: overrides)
    }

    /// Current state of the quest `id` names, or nil when no quest does.
    public func state(for id: FormID) -> QuestRuntimeState? {
        guard let quest = defaults.quest(id) else { return nil }
        guard let key = defaults.key(for: id), let override = overrides[key] else {
            return QuestRuntimeState.baseline(for: quest)
        }
        return override
    }

    public func state(editorID: String) -> QuestRuntimeState? {
        guard let id = defaults.formID(editorID: editorID) else { return nil }
        return state(for: id)
    }

    /// True when the session has recorded runtime state for `id`, as opposed to
    /// the quest still reading straight from plugin data.
    public func hasRuntimeState(_ id: FormID) -> Bool {
        guard let key = defaults.key(for: id) else { return false }
        return overrides[key] != nil
    }

    /// Quests with runtime state in this resolution.
    public var runtimeStateCount: Int {
        overrides.count
    }
}

nonisolated extension QuestResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// The one seam quest state comes through, shaped exactly like
    /// the globals seam: a value resolving overrides over plugin baselines, so
    /// the quest functions never reach into `WorldStateStore`.
    public var quests: QuestResolution {
        get { self[resolution: QuestResolution.self] }
        set {
            self[resolution: QuestResolution.self] = newValue
        }
    }
}
