// `BSiStateTaggingGenerator`: while it runs, the graph reports one `iState` value, such as
// `MT_Drunk_iStateGen` in `mt_behavior.hkx`. The tag with the highest priority wins
// (docs/engine/actor-state-graph.md).

import Foundation
import OpenSkyFormatsAnimation

/// One `iState` value a running state tagging generator publishes.
nonisolated public struct BehaviorStateTag: Equatable, Sendable {
    public let value: Int32
    public let priority: Int

    public init(value: Int32, priority: Int) {
        self.value = value
        self.priority = priority
    }
}

nonisolated extension BehaviorGraphInstance {
    /// Keeps `tag` when it outranks the tag chosen so far. On a tie the first one reached
    /// stays; no source states the game's tie rule.
    func noteStateTag(_ tag: BehaviorStateTag) {
        if let current = stateTagThisUpdate, current.priority >= tag.priority {
            return
        }
        stateTagThisUpdate = tag
    }

    /// Notes the tag of `tagging`, with its bound values when the graph binds them.
    func noteStateTag(
        of tagging: BSiStateTaggingGenerator, bound: [String: BehaviorVariableValue]
    ) {
        noteStateTag(BehaviorStateTag(
            value: Int32(truncatingIfNeeded: bound.int("iStateToSetAs", or: tagging.stateToSetAs)),
            priority: bound.int("iPriority", or: tagging.priority)
        ))
    }

    /// True when the last update's tag holds the value of the constant `name`, such as
    /// `iState_NPCDrunk`.
    public func isTaggingState(_ name: String) -> Bool {
        guard let tag = stateTag, let constant = variable(named: name) else { return false }
        return tag.value == Int32(truncatingIfNeeded: constant.intValue)
    }
}
