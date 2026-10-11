// Which clip a behavior event starts, read from the graph without running it.
// A transition on the event leads to a state; a machine below it starts in its
// start state, and the first clip there is the answer. A behavior reference
// passes the event on to the referenced file. See docs/engine/idle-runtime.md.

import Foundation
import OpenSkyFormatsAnimation

/// The clip one event reaches, and the behavior files the lookup walked.
nonisolated public struct BehaviorEventClip: Equatable, Sendable {
    /// The clip generator's animation name, relative to the project folder.
    public let animationName: String
    public var behaviorFiles: [String]
    /// String payloads of events below the target state, in walk order. A prop
    /// event such as `AnimObjDraw` names its ANIO editor ID here.
    public var payloads: [String]
    /// The target state's notify events. A cart exit state sends `ExitCartEnd` on exit.
    public var notify = BehaviorStateNotify()
    /// The clip generator loops (`m_mode` 1, or 3 ping pong), so the state holds
    /// until an event leaves it.
    public var loops = false
    /// The state the event enters, so a live graph can tell that it took the event.
    public var stateName: String?
    /// Events the clip generator raises as it plays, such as `KillActor`.
    public var triggers: [BehaviorClipTriggerEvent] = []
    /// Clips the state's own triggers lead on to, in order, such as an enter clip
    /// whose `ExecutionNextClip` leads to the seat's idle loop.
    public var followUps: [BehaviorClipSegment] = []
    /// Where the chain ends, so the next event is looked up from there.
    public var position: BehaviorStatePosition?
}

/// One state of one machine in one behavior file, as a reference spells the file.
nonisolated public struct BehaviorStatePosition: Hashable, Sendable {
    public let file: String
    public let machine: HKXPointerTarget
    public let state: Int

    public init(file: String, machine: HKXPointerTarget, state: Int) {
        self.file = file
        self.machine = machine
        self.state = state
    }
}

/// A clip that a chain plays after the first one.
nonisolated public struct BehaviorClipSegment: Equatable, Sendable {
    public let animationName: String
    public let loops: Bool
    public let triggers: [BehaviorClipTriggerEvent]
    public let stateName: String?
}

/// An event a clip generator raises. A time from the end is negative.
nonisolated public struct BehaviorClipTriggerEvent: Equatable, Sendable {
    public let name: String
    public let time: Float
    public let fromEnd: Bool

    public init(name: String, time: Float, fromEnd: Bool) {
        self.name = name
        self.time = time
        self.fromEnd = fromEnd
    }

    /// Seconds from the clip start, inside the clip.
    public func seconds(inClipOf duration: Float) -> Float {
        min(max(fromEnd ? duration + time : time, 0), duration)
    }
}

/// Event names a state sends when the machine enters it and when it leaves it.
nonisolated public struct BehaviorStateNotify: Equatable, Sendable {
    public var enter: [String]
    public var exit: [String]

    public init(enter: [String] = [], exit: [String] = []) {
        self.enter = enter
        self.exit = exit
    }
}

/// Event lookups over a set of behavior files, decoded once each. The loader
/// takes a file name as a behavior reference spells it.
nonisolated public final class BehaviorEventClipIndex {
    public typealias Loader = (String) -> HKXObjectGraph?

    struct GraphEvents {
        let graph: HKXObjectGraph
        let names: [String?]
        let root: HKXPointerTarget?
        /// Lowercased event name -> the generators its transitions lead to,
        /// deepest state machine first, because an inner machine picks the clip.
        let targets: [String: [HKXPointerTarget]]
        /// The notify events of the state each target generator belongs to.
        let notify: [HKXPointerTarget: BehaviorStateNotify]
        let stateNames: [HKXPointerTarget: String]
        /// Behavior files the graph references, in walk order.
        let references: [String]
    }

    static let maximumReferenceDepth = 8

    private let load: Loader
    private var graphs: [String: GraphEvents?] = [:]

    public init(load: @escaping Loader) {
        self.load = load
    }

    /// The clip `event` starts in `behaviorFile`, or nil when no transition in
    /// the file or the files it references names the event.
    /// From `position`, a transition of the actor's own state or machine wins, because
    /// one event such as `IdleExecutionerChop` leads each role's machine to its own clip.
    public func clip(
        forEvent event: String, behaviorFile: String, from position: BehaviorStatePosition? = nil
    ) -> BehaviorEventClip? {
        let name = event.lowercased()
        let found = position.flatMap { clip(forEvent: name, at: $0) }
            ?? clip(forEvent: name, file: behaviorFile, depth: 0)
        return found.map(chained)
    }

    func clip(forEvent event: String, file: String, depth: Int) -> BehaviorEventClip? {
        guard depth < Self.maximumReferenceDepth, let events = graphEvents(file) else {
            return nil
        }
        for target in events.targets[event] ?? [] {
            if
                var found = entryClip(from: target, file: file, event: event, depth: depth)
            {
                found.behaviorFiles = [file] + found.behaviorFiles
                found.payloads = Self.payloads(below: target, in: events.graph) + found.payloads
                found.notify = events.notify[target] ?? found.notify
                found.stateName = events.stateNames[target] ?? found.stateName
                return found
            }
        }
        // A sub-behavior takes events while its state is active, so a transition
        // there answers too.
        for reference in events.references {
            if var found = clip(forEvent: event, file: reference, depth: depth + 1) {
                found.behaviorFiles = [file] + found.behaviorFiles
                return found
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

    func graphEvents(_ file: String) -> GraphEvents? {
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
        var notify: [HKXPointerTarget: BehaviorStateNotify] = [:]
        var stateNames: [HKXPointerTarget: String] = [:]
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
                for transition in transitions(of: machine, in: graph) {
                    guard
                        names.indices.contains(transition.eventID),
                        let name = names[transition.eventID]
                    else {
                        continue
                    }
                    let state = transition.state
                    found[name.lowercased(), default: []].append((node.depth, transition.generator))
                    notify[transition.generator] = BehaviorStateNotify(
                        enter: eventNames(state.enterNotifyEvents, names: names, in: graph),
                        exit: eventNames(state.exitNotifyEvents, names: names, in: graph)
                    )
                    stateNames[transition.generator] = state.name
                }
            }
        }
        let targets = found.mapValues { entries in
            entries.enumerated()
                .sorted { ($0.element.depth, -$0.offset) > ($1.element.depth, -$1.offset) }
                .map(\.element.target)
        }
        return GraphEvents(
            graph: graph, names: names, root: behavior.rootGenerator, targets: targets,
            notify: notify,
            stateNames: stateNames, references: references
        )
    }

    static func eventNames(
        _ array: HKXPointerTarget?, names: [String?], in graph: HKXObjectGraph
    ) -> [String] {
        guard let array, let events = HKBStateMachineEventPropertyArray.decode(at: array, in: graph)
        else { return [] }
        return events.events.compactMap { names.indices.contains($0.id) ? names[$0.id] : nil }
    }

    /// `FLAG_TO_NESTED_STATE_ID_IS_VALID` (docs/engine/behavior-state-machines.md).
    private static let toNestedStateFlag = 0x2000

    /// One transition's event index, and the generator and info of the state it enters.
    struct EventTransition {
        let eventID: Int
        let generator: HKXPointerTarget
        let state: HKBStateMachineStateInfo
    }

    /// Each transition of one state machine, into the state it enters or the nested
    /// state it names.
    static func transitions(
        of machine: HKBStateMachine,
        in graph: HKXObjectGraph
    ) -> [EventTransition] {
        let states = states(of: machine, in: graph)
        return transitions(
            in: [machine.wildcardTransitions] + states.map(\.transitions),
            states: states,
            graph: graph
        )
    }

    /// The transitions of the given arrays, into the state each enters or the nested
    /// state it names.
    static func transitions(
        in arrays: [HKXPointerTarget?],
        states: [HKBStateMachineStateInfo],
        graph: HKXObjectGraph
    ) -> [EventTransition] {
        arrays.compactMap(\.self)
            .compactMap { HKBStateMachineTransitionInfoArray.decode(at: $0, in: graph) }
            .flatMap(\.transitions)
            .compactMap { transition in
                guard
                    transition.eventId >= 0,
                    let state = states.first(where: { $0.stateId == transition.toStateId }),
                    let target = state.generator
                else { return nil }
                // A modifier generator may wrap the nested machine, so take the
                // first machine below the target.
                guard
                    transition.flags & toNestedStateFlag != 0,
                    let nested = HKBGraphTopology.walk(from: target, in: graph).nodes
                        .lazy.compactMap({ $0.object as? HKBStateMachine }).first,
                    let innerState = Self.states(of: nested, in: graph)
                        .first(where: { $0.stateId == transition.toNestedStateId }),
                    let inner = innerState.generator
                else { return EventTransition(
                    eventID: transition.eventId,
                    generator: target,
                    state: state
                ) }
                return EventTransition(
                    eventID: transition.eventId,
                    generator: inner,
                    state: innerState
                )
            }
    }

    static func states(
        of machine: HKBStateMachine,
        in graph: HKXObjectGraph
    ) -> [HKBStateMachineStateInfo] {
        machine.states.compactMap(\.self)
            .compactMap { HKBStateMachineStateInfo.decode(at: $0, in: graph) }
    }
}
