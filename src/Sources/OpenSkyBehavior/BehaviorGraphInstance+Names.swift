// Name lookups across a character's graph files. Havok links the event and variable names
// of the root and every referenced file into one table per character
// (docs/engine/behavior-clips.md).

nonisolated extension BehaviorGraphInstance {
    /// A name only a referenced graph declares, such as `bIsSynced` in `1hm_behavior.hkx`,
    /// is read from the first running graph that declares it.
    public func variable(named name: String) -> BehaviorVariableValue? {
        if let value = variables.value(of: name) {
            return value
        }
        return referencedGraphs.values.lazy
            .compactMap { child in child.flatMap { $0.isActive ? $0.variable(named: name) : nil } }
            .first
    }

    /// Raises an event by name, visible to the *next* update. A name only a referenced graph
    /// declares, such as a kill move in `1hm_behavior.hkx`, is passed down to it by name.
    @discardableResult
    public func raiseEvent(named name: String, payload: String? = nil) -> Bool {
        if events.raise(named: name, payload: payload) {
            return true
        }
        guard referencedGraphDeclares(name) else { return false }
        events.raise(undeclared: name, payload: payload)
        return true
    }

    func referencedGraphDeclares(_ name: String) -> Bool {
        referencedGraphs.values.contains { child in
            guard let child else { return false }
            return child.events.index(of: name) != nil || child.referencedGraphDeclares(name)
        }
    }
}
