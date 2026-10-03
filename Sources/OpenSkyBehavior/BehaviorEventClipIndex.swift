// Which clip a behavior event starts, read from the graph without running it.
// A transition on the event leads to a state; the first clip under that state
// is the answer. A behavior reference passes the event on to the referenced
// file. See docs/engine/idle-runtime.md.

import Foundation
import OpenSkyFormatsAnimation

/// The clip one event reaches, and the behavior files the lookup walked.
nonisolated public struct BehaviorEventClip: Equatable, Sendable {
    /// The clip generator's animation name, relative to the project folder.
    public let animationName: String
    public let behaviorFiles: [String]
    /// String payloads of events below the target state, in walk order. A prop
    /// event such as `AnimObjDraw` names its ANIO editor ID here.
    public let payloads: [String]
}

/// Event lookups over a set of behavior files, decoded once each. The loader
/// takes a file name as a behavior reference spells it.
nonisolated public final class BehaviorEventClipIndex {
    public typealias Loader = (String) -> HKXObjectGraph?

    private struct GraphEvents {
        let graph: HKXObjectGraph
        let root: HKXPointerTarget?
        /// Lowercased event name -> the generators its transitions lead to,
        /// deepest state machine first, because an inner machine picks the clip.
        let targets: [String: [HKXPointerTarget]]
        /// Behavior files the graph references, in walk order.
        let references: [String]
    }

    private static let maximumReferenceDepth = 8

    private let load: Loader
    private var graphs: [String: GraphEvents?] = [:]

    public init(load: @escaping Loader) {
        self.load = load
    }

    /// The clip `event` starts in `behaviorFile`, or nil when no transition in
    /// the file or the files it references names the event.
    public func clip(forEvent event: String, behaviorFile: String) -> BehaviorEventClip? {
        clip(forEvent: event.lowercased(), file: behaviorFile, depth: 0)
    }

    private func clip(forEvent event: String, file: String, depth: Int) -> BehaviorEventClip? {
        guard depth < Self.maximumReferenceDepth, let events = graphEvents(file) else {
            return nil
        }
        for target in events.targets[event] ?? [] {
            if let found = firstClip(from: target, in: events.graph, event: event, depth: depth) {
                return BehaviorEventClip(
                    animationName: found.animationName,
                    behaviorFiles: [file] + found.behaviorFiles,
                    payloads: Self.payloads(below: target, in: events.graph) + found.payloads
                )
            }
        }
        // A sub-behavior takes events while its state is active, so a transition
        // there answers too.
        for reference in events.references {
            if let found = clip(forEvent: event, file: reference, depth: depth + 1) {
                return BehaviorEventClip(
                    animationName: found.animationName,
                    behaviorFiles: [file] + found.behaviorFiles,
                    payloads: found.payloads
                )
            }
        }
        return nil
    }

    /// The first clip below `target` in walk order. A behavior reference on the
    /// way is searched for the same event first, then for its start clip.
    private func firstClip(
        from target: HKXPointerTarget,
        in graph: HKXObjectGraph,
        event: String,
        depth: Int
    ) -> BehaviorEventClip? {
        for node in HKBGraphTopology.walk(from: target, in: graph).nodes {
            if let clip = node.object as? HKBClipGenerator, let name = clip.animationName {
                return BehaviorEventClip(animationName: name, behaviorFiles: [], payloads: [])
            }
            guard
                let reference = node.object as? HKBBehaviorReferenceGenerator,
                let name = reference.behaviorName
            else { continue }
            if let found = clip(forEvent: event, file: name, depth: depth + 1) {
                return found
            }
            if
                let events = graphEvents(name), let root = events.root,
                let found = firstClip(from: root, in: events.graph, event: "", depth: depth + 1)
            {
                return BehaviorEventClip(
                    animationName: found.animationName,
                    behaviorFiles: [name] + found.behaviorFiles,
                    payloads: found.payloads
                )
            }
        }
        return nil
    }

    private static func payloads(below target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> [String]
    {
        HKBGraphTopology.walk(from: target, in: graph).nodes
            .compactMap { ($0.object as? HKBStringEventPayload)?.data }
    }

    private func graphEvents(_ file: String) -> GraphEvents? {
        let key = file.lowercased()
        if let cached = graphs[key] {
            return cached
        }
        let events = load(file).flatMap(Self.events)
        graphs[key] = events
        return events
    }

    private static func events(in graph: HKXObjectGraph) -> GraphEvents? {
        guard let behavior = HKBBehaviorGraph.graphs(in: graph).first else { return nil }
        let names = behavior.data?.stringData?.eventNames ?? []
        var found: [String: [(depth: Int, target: HKXPointerTarget)]] = [:]
        var references: [String] = []
        if let root = behavior.rootGenerator {
            for node in HKBGraphTopology.walk(from: root, in: graph).nodes {
                if
                    let reference = node.object as? HKBBehaviorReferenceGenerator,
                    let name = reference.behaviorName, !references.contains(name)
                {
                    references.append(name)
                }
                guard let machine = node.object as? HKBStateMachine else { continue }
                for (eventID, generator) in transitions(of: machine, in: graph) {
                    guard names.indices.contains(eventID), let name = names[eventID] else {
                        continue
                    }
                    found[name.lowercased(), default: []].append((node.depth, generator))
                }
            }
        }
        let targets = found.mapValues { entries in
            entries.enumerated()
                .sorted { ($0.element.depth, -$0.offset) > ($1.element.depth, -$1.offset) }
                .map(\.element.target)
        }
        return GraphEvents(
            graph: graph, root: behavior.rootGenerator, targets: targets, references: references
        )
    }

    /// `FLAG_TO_NESTED_STATE_ID_IS_VALID` (docs/engine/behavior-state-machines.md).
    private static let toNestedStateFlag = 0x2000

    /// Each transition of one state machine as its event index and the
    /// generator of the state it enters, or of the nested state it names.
    private static func transitions(
        of machine: HKBStateMachine,
        in graph: HKXObjectGraph
    ) -> [(Int, HKXPointerTarget)] {
        let states = states(of: machine, in: graph)
        let arrays = [machine.wildcardTransitions] + states.map(\.transitions)
        return arrays.compactMap(\.self)
            .compactMap { HKBStateMachineTransitionInfoArray.decode(at: $0, in: graph) }
            .flatMap(\.transitions)
            .compactMap { transition in
                guard
                    transition.eventId >= 0,
                    let target = states.first(where: { $0.stateId == transition.toStateId })?
                        .generator
                else { return nil }
                // A modifier generator may wrap the nested machine, so take the
                // first machine below the target.
                guard
                    transition.flags & toNestedStateFlag != 0,
                    let nested = HKBGraphTopology.walk(from: target, in: graph).nodes
                        .lazy.compactMap({ $0.object as? HKBStateMachine }).first,
                    let inner = Self.states(of: nested, in: graph)
                        .first(where: { $0.stateId == transition.toNestedStateId })?.generator
                else { return (transition.eventId, target) }
                return (transition.eventId, inner)
            }
    }

    private static func states(
        of machine: HKBStateMachine,
        in graph: HKXObjectGraph
    ) -> [HKBStateMachineStateInfo] {
        machine.states.compactMap(\.self)
            .compactMap { HKBStateMachineStateInfo.decode(at: $0, in: graph) }
    }
}
