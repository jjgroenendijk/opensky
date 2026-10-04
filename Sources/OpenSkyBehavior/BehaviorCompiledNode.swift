// One decoded node plus what every update would otherwise derive from it again: its
// child targets, its binding set, and the bindings' normalized member paths. Built on
// the node's first reach and kept, because a graph's shape is fixed after load.

import OpenSkyFormatsAnimation

nonisolated public struct BehaviorCompiledNode {
    public let object: any HKBClass
    /// Every reference target, in declared order.
    public let children: [HKXPointerTarget]
    /// The node's `m_variableBindingSet`, or nil when it has none.
    public let bindings: BehaviorCompiledBindings?
}

nonisolated public struct BehaviorCompiledBindings {
    public let bindings: [HKBVariableBinding]
    /// Each binding's member path without the `m_` prefix; nil for an empty path.
    public let paths: [String?]
    /// The binding that drives the node's enable flag, when the index is in range.
    public let enableIndex: Int?

    init(_ set: HKBVariableBindingSet) {
        bindings = set.bindings
        paths = set.bindings.map { binding in
            guard let path = binding.memberPath, !path.isEmpty else { return nil }
            return BehaviorGraphInstance.normalizedMemberPath(path)
        }
        enableIndex = set.bindings.indices.contains(set.indexOfBindingToEnable)
            ? set.indexOfBindingToEnable : nil
    }
}
