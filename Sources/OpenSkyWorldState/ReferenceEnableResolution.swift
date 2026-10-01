// Immutable reference enable-state seam for condition evaluation. A package selector
// passes snapshot answers without reaching into the main-actor store.

import OpenSkyFormatsESM

nonisolated public struct ReferenceEnableResolution: Sendable {
    public static let empty = ReferenceEnableResolution(states: [:])

    private let states: [ReferenceKey: ReferenceEnableState]

    public init(states: [ReferenceKey: ReferenceEnableState]) {
        self.states = states
    }

    public init(snapshot: WorldStateSnapshot) {
        states = Dictionary(uniqueKeysWithValues: snapshot.entries.compactMap { entry in
            entry.delta.component(ReferenceEnableState.self).map { (entry.key, $0) }
        })
    }

    public subscript(key: ReferenceKey) -> ReferenceEnableState? {
        states[key]
    }
}
