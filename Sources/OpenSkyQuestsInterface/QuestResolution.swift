// The one place that answers "what is this quest's state now?". A runtime state
// wins, then the plugin baseline; nil means no such quest. A build thread can
// read it from a snapshot. See docs/engine/quest-state.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

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
