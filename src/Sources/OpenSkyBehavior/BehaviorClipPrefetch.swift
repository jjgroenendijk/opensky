// Finds the clips a graph plays from its start states, so an off-main clip source
// can read them before the first update asks. A state machine is followed into its
// start state only; every other node into all of its children.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// Asks the clip source to prefetch every clip the start states reach.
    public func prefetchReachableClips() {
        var names: [String] = []
        var visited: Set<HKXPointerTarget> = []
        collectClipNames(at: root, depth: 0, visited: &visited, into: &names)
        var seen: Set<String> = []
        for name in names where seen.insert(name.lowercased()).inserted {
            clipSource.prefetch(named: name)
        }
    }

    private func collectClipNames(
        at target: HKXPointerTarget?,
        depth: Int,
        visited: inout Set<HKXPointerTarget>,
        into names: inout [String]
    ) {
        guard
            let target, depth < Self.maximumDepth, visited.insert(target).inserted,
            let node = compiledNode(at: target)
        else { return }
        switch node.object {
        case let clip as HKBClipGenerator:
            if let name = clip.animationName {
                names.append(name)
            }
        case let machine as HKBStateMachine:
            let start = stateInfo(of: machine, id: machine.startStateId)?.info.generator
            collectClipNames(at: start, depth: depth + 1, visited: &visited, into: &names)
        case let reference as HKBBehaviorReferenceGenerator:
            guard let name = reference.behaviorName, let child = referencedGraph(named: name)
            else { return }
            // Pointer targets are per file, so the child starts its own visited set.
            var childVisited: Set<HKXPointerTarget> = []
            child.collectClipNames(
                at: child.root, depth: depth + 1, visited: &childVisited, into: &names
            )
        default:
            for child in node.children {
                collectClipNames(at: child, depth: depth + 1, visited: &visited, into: &names)
            }
        }
    }
}
