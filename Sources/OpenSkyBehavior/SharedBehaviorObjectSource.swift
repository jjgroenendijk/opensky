// Decodes each object of one behaviour file once for every graph built over that file.
// All actors of a race run one graph file, so they share its decode too.

import OpenSkyFormatsAnimation

/// A `BehaviorObjectSource` that keeps each decode. Build one per decoded file and hand it
/// to every instance over that file. Not `Sendable`: its owner keeps it on one actor.
nonisolated public final class SharedBehaviorObjectSource: BehaviorObjectSource {
    private let graph: HKXObjectGraph
    /// The optional is stored so an object with no decoder is tried once.
    private var decoded: [HKXPointerTarget: (any HKBClass)?] = [:]

    public init(graph: HKXObjectGraph) {
        self.graph = graph
    }

    public func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        if let cached = decoded[target] {
            return cached
        }
        let object = HKBClassRegistry.decode(at: target, in: graph)
        decoded[target] = .some(object)
        return object
    }

    public func className(at target: HKXPointerTarget) -> String? {
        graph.className(at: target)
    }
}
