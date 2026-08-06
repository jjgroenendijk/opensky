// Walking a decoded behavior graph (todo 14.2). Two views over the same
// registry: `HKBGraphTopology` follows the node tree down from a root
// generator, which is what the CLI dump and the 14.3 evaluator want, and
// `HKBDecodeReport` decodes every registered object in a file regardless of
// reachability, which is what the env-gated sweep asserts against.
//
// Both are counts and names only. Nothing extracted from the install may enter
// the repository (AGENTS.md Legal & IP), so a report carries class names,
// node names, and totals, never sample bytes.

import Foundation

/// One node of a walked graph: where it lives, what it decoded to, and how deep
/// below the root it was first reached.
nonisolated struct HKBGraphNode {
    let target: HKXPointerTarget
    let object: any HKBClass
    let depth: Int
}

/// The node tree below one root generator, in first-visit order.
nonisolated struct HKBGraphTopology {
    let nodes: [HKBGraphNode]
    /// Class names reached but not decodable, with how many objects each cost.
    let skippedClassCounts: [String: Int]
    /// References that pointed at a location registering no class at all.
    let unregisteredTargetCount: Int
    let unresolved: [HKXUnresolvedReference]

    /// Depth-first, first-visit-wins walk from `root`. A behavior graph is a
    /// DAG rather than a tree — a transition effect or a bone weight array is
    /// shared by many nodes — so visited targets are tracked and a repeat
    /// reference is not re-decoded.
    static func walk(from root: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBGraphTopology
    {
        var nodes: [HKBGraphNode] = []
        var skipped: [String: Int] = [:]
        var unregistered = 0
        var unresolved: [HKXUnresolvedReference] = []
        var visited: Set<HKXPointerTarget> = []
        var stack: [(target: HKXPointerTarget, depth: Int)] = [(root, 0)]

        while let (target, depth) = stack.popLast() {
            guard visited.insert(target).inserted else { continue }
            guard let className = graph.className(at: target) else {
                unregistered += 1
                continue
            }
            guard let object = HKBClassRegistry.decoder(for: className)?(target, graph)
            else {
                skipped[className, default: 0] += 1
                continue
            }
            nodes.append(HKBGraphNode(target: target, object: object, depth: depth))
            unresolved += object.unresolved
            // Reversed so the first member is popped first and the dump reads
            // in the order the class declares its members.
            for reference in object.references.reversed() {
                stack.append((reference.target, depth + 1))
            }
        }
        return HKBGraphTopology(
            nodes: nodes,
            skippedClassCounts: skipped,
            unregisteredTargetCount: unregistered,
            unresolved: unresolved
        )
    }

    /// Every walked node of one class, in visit order.
    func nodes(ofClass className: String) -> [HKBGraphNode] {
        nodes.filter { $0.object.className == className }
    }
}

/// The result of decoding every registered object in one packfile: what
/// decoded, what had no decoder, and every field that failed to resolve. This
/// is the sweep's evidence that the layouts in this milestone are right.
nonisolated struct HKBDecodeReport {
    /// Objects decoded per class name.
    let decodedCounts: [String: Int]
    /// Objects whose class has no registered decoder, per class name. Under the
    /// full-graph rule this must be empty for a player behavior file.
    let skippedCounts: [String: Int]
    /// Objects whose class has a decoder that still returned nil — a cursor
    /// that could not be placed, which means a corrupt object offset.
    let failedCounts: [String: Int]
    let unresolved: [HKXUnresolvedReference]

    var decodedTotal: Int {
        decodedCounts.values.reduce(0, +)
    }

    var skippedTotal: Int {
        skippedCounts.values.reduce(0, +)
    }

    var failedTotal: Int {
        failedCounts.values.reduce(0, +)
    }

    /// Class names the file declares that no decoder covers, sorted for a
    /// stable assertion message.
    var uncoveredClassNames: [String] {
        skippedCounts.keys.sorted()
    }

    /// Decodes every object the packfile registers. Graph-level classes from
    /// item 14.1 are counted as covered rather than decoded again, because
    /// `HKBBehaviorCensus` already walks those and decoding them twice would
    /// double-count their misses.
    static func decodeAll(in graph: HKXObjectGraph) -> HKBDecodeReport {
        var decoded: [String: Int] = [:]
        var skipped: [String: Int] = [:]
        var failed: [String: Int] = [:]
        var unresolved: [HKXUnresolvedReference] = []

        for object in graph.file.objects {
            guard let className = object.className else {
                skipped["<unresolved>", default: 0] += 1
                continue
            }
            if HKBClassRegistry.graphLevelClassNames.contains(className) {
                decoded[className, default: 0] += 1
                continue
            }
            guard let decoder = HKBClassRegistry.decoder(for: className) else {
                skipped[className, default: 0] += 1
                continue
            }
            let target = HKXPointerTarget(
                sectionIndex: object.sectionIndex, dataOffset: object.dataOffset
            )
            guard let value = decoder(target, graph) else {
                failed[className, default: 0] += 1
                continue
            }
            decoded[className, default: 0] += 1
            unresolved += value.unresolved
        }
        return HKBDecodeReport(
            decodedCounts: decoded,
            skippedCounts: skipped,
            failedCounts: failed,
            unresolved: unresolved
        )
    }
}
