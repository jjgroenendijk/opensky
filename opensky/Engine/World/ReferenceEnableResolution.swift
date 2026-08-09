// Immutable reference enable-state seam for condition evaluation (issue
// #201). A package selector can pass a WorldState snapshot's answers without
// letting the condition registry reach into the main-actor store.

nonisolated struct ReferenceEnableResolution: Sendable {
    static let empty = ReferenceEnableResolution(states: [:])

    private let states: [ReferenceKey: ReferenceEnableState]

    init(states: [ReferenceKey: ReferenceEnableState]) {
        self.states = states
    }

    init(snapshot: WorldStateSnapshot) {
        states = Dictionary(uniqueKeysWithValues: snapshot.entries.compactMap { entry in
            entry.delta.component(ReferenceEnableState.self).map { (entry.key, $0) }
        })
    }

    subscript(key: ReferenceKey) -> ReferenceEnableState? {
        states[key]
    }
}
