// Which clip triggers make a graph leave the state an idle enters. A trigger leaves
// when a transition on its event starts from that state or from a state that holds
// it, or when it is a global wildcard anywhere in the actor's behaviour files.
// See docs/engine/vehicles.md#how-an-exit-state-ends.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorEventClipIndex {
    /// The lowercased events that take the graph out of the state that plays `clip`, or
    /// out of a state that holds it, read from the files `behaviorFile` reaches.
    func leavingEvents(of clip: BehaviorClipNode, behaviorFile: String) -> Set<String> {
        globalWildcardEvents(from: behaviorFile).union(enclosingEvents(of: clip))
    }

    /// Each event a state on the way up from the clip leaves on: its own transitions and
    /// the wildcards of the machine that holds it.
    private func enclosingEvents(of clip: BehaviorClipNode) -> Set<String> {
        guard let events = graphEvents(clip.file) else { return [] }
        let parents = parentLinks(clip.file, events: events)
        var found: Set<String> = []
        var visited: Set<HKXPointerTarget> = []
        var next: HKXPointerTarget? = clip.target
        while let target = next, visited.insert(target).inserted {
            switch decoded(target, in: events.graph) {
            case let state as HKBStateMachineStateInfo:
                found.formUnion(Self.eventNames(of: [state.transitions], events: events))
            case let machine as HKBStateMachine:
                found.formUnion(Self.eventNames(of: [machine.wildcardTransitions], events: events))
            default:
                break
            }
            next = parents[target]
        }
        return found
    }

    /// The events of every global wildcard in `file` and the files it references.
    private func globalWildcardEvents(from file: String) -> Set<String> {
        var found: Set<String> = []
        var files = [file]
        var seen: Set<String> = []
        while let name = files.popLast(), seen.count < 64 {
            guard seen.insert(name.lowercased()).inserted, let events = graphEvents(name) else {
                continue
            }
            files += events.references
            guard let root = events.root else { continue }
            for node in HKBGraphTopology.walk(from: root, in: events.graph).nodes {
                guard let machine = node.object as? HKBStateMachine else { continue }
                found.formUnion(Self.eventNames(
                    of: [machine.wildcardTransitions], events: events,
                    where: { $0 & BehaviorTransitionFlag.globalWildcard != 0 }
                ))
            }
        }
        return found
    }

    /// Each object's parent in the file, found once by a walk from the root.
    private func parentLinks(
        _ file: String, events: GraphEvents
    ) -> [HKXPointerTarget: HKXPointerTarget] {
        let key = file.lowercased()
        if let known = parents[key] {
            return known
        }
        var links: [HKXPointerTarget: HKXPointerTarget] = [:]
        var stack = events.root.map { [$0] } ?? []
        var visited: Set<HKXPointerTarget> = []
        while let target = stack.popLast() {
            guard
                visited.insert(target).inserted,
                let object = decoded(target, in: events.graph)
            else { continue }
            for child in object.references where links[child.target] == nil {
                links[child.target] = target
                stack.append(child.target)
            }
        }
        parents[key] = links
        return links
    }

    private func decoded(_ target: HKXPointerTarget, in graph: HKXObjectGraph) -> (any HKBClass)? {
        graph.className(at: target).flatMap { HKBClassRegistry.decoder(for: $0)?(target, graph) }
    }

    private static func eventNames(
        of arrays: [HKXPointerTarget?], events: GraphEvents,
        where keep: (Int) -> Bool = { _ in true }
    ) -> Set<String> {
        Set(arrays.compactMap(\.self)
            .compactMap { HKBStateMachineTransitionInfoArray.decode(at: $0, in: events.graph) }
            .flatMap(\.transitions)
            .filter { $0.eventId >= 0 && keep($0.flags) }
            .compactMap { transition in
                events.names.indices.contains(transition.eventId)
                    ? events.names[transition.eventId]?.lowercased() : nil
            })
    }
}
