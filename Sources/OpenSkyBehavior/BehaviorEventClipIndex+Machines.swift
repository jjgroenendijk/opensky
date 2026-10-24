// How the static clip lookup moves through state machines: a machine starts in
// its start state, a clip's own triggers lead on to the next state, and an actor
// that sits in a state takes an event there first. See docs/engine/idle-runtime.md.

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorEventClipIndex {
    /// A chain stops after this many clips, so a cycle of triggers cannot hang it.
    private static let maximumFollowUps = 4

    /// The clip a machine plays first below `target`: each machine on the way enters
    /// its start state. A behavior reference is searched for `event` first.
    func entryClip(
        from target: HKXPointerTarget, file: String, event: String, depth: Int
    ) -> BehaviorEventClip? {
        guard let events = graphEvents(file) else { return nil }
        var visited: Set<HKXPointerTarget> = []
        let descent = Descent(events: events, file: file, event: event, depth: depth)
        return descend(target, descent, position: nil, visited: &visited)
    }

    /// What stays the same down one descent.
    private struct Descent {
        let events: GraphEvents
        let file: String
        let event: String
        let depth: Int
    }

    private func descend(
        _ target: HKXPointerTarget, _ descent: Descent,
        position: BehaviorStatePosition?, visited: inout Set<HKXPointerTarget>
    ) -> BehaviorEventClip? {
        let events = descent.events
        guard
            visited.insert(target).inserted,
            let className = events.graph.className(at: target),
            let object = HKBClassRegistry.decoder(for: className)?(target, events.graph)
        else { return nil }
        if let clip = object as? HKBClipGenerator {
            guard let name = clip.animationName else { return nil }
            var found = BehaviorEventClip(
                animationName: name, behaviorFiles: [], payloads: [],
                loops: clip.mode == 1 || clip.mode == 3
            )
            found.triggers = Self.triggers(of: clip, in: events)
            found.generatorName = clip.node.name
            found.position = position
            return found
        }
        if let machine = object as? HKBStateMachine {
            let states = Self.states(of: machine, in: events.graph)
            guard
                let start = states.first(where: { $0.stateId == machine.startStateId })
                ?? states.first,
                let generator = start.generator
            else { return nil }
            let entered = BehaviorStatePosition(
                file: descent.file, machine: target, state: start.stateId
            )
            return descend(generator, descent, position: entered, visited: &visited)
        }
        if let reference = object as? HKBBehaviorReferenceGenerator {
            return referencedClip(reference, event: descent.event, depth: descent.depth)
        }
        for child in object.references {
            if let found = descend(child.target, descent, position: position, visited: &visited) {
                return found
            }
        }
        return nil
    }

    private func referencedClip(
        _ reference: HKBBehaviorReferenceGenerator, event: String, depth: Int
    ) -> BehaviorEventClip? {
        guard let name = reference.behaviorName, depth + 1 < Self.maximumReferenceDepth else {
            return nil
        }
        if var found = clip(forEvent: event, file: name, depth: depth + 1) {
            found.behaviorFiles = [name] + found.behaviorFiles
            return found
        }
        guard
            let events = graphEvents(name), let root = events.root,
            var found = entryClip(from: root, file: name, event: "", depth: depth + 1)
        else { return nil }
        found.behaviorFiles = [name] + found.behaviorFiles
        return found
    }

    /// A transition of the state at `position`, or a wildcard of its machine.
    func clip(forEvent event: String, at position: BehaviorStatePosition) -> BehaviorEventClip? {
        guard
            let transition = transition(on: { $0 == event }, at: position),
            var found = entryClip(
                from: transition.generator, file: position.file, event: event, depth: 0
            )
        else { return nil }
        found.behaviorFiles = [position.file] + found.behaviorFiles
        found.stateName = transition.state.name ?? found.stateName
        if found.position == nil {
            found.position = BehaviorStatePosition(
                file: position.file, machine: position.machine, state: transition.state.stateId
            )
        }
        return found
    }

    /// Adds the clips a non-looping clip's own triggers lead to.
    func chained(_ clip: BehaviorEventClip) -> BehaviorEventClip {
        var result = clip
        var loops = clip.loops
        var triggers = clip.triggers
        for _ in 0 ..< Self.maximumFollowUps {
            guard
                !loops, let position = result.position,
                let next = followUp(of: triggers, at: position)
            else { break }
            result.followUps.append(BehaviorClipSegment(
                animationName: next.animationName, loops: next.loops,
                triggers: next.triggers
            ))
            result.position = next.position
            loops = next.loops
            triggers = next.triggers
        }
        return result
    }

    private func followUp(
        of triggers: [BehaviorClipTriggerEvent], at position: BehaviorStatePosition
    ) -> BehaviorEventClip? {
        let names = Set(triggers.map { $0.name.lowercased() })
        guard !names.isEmpty else { return nil }
        guard
            let transition = transition(on: { names.contains($0) }, at: position),
            var found = entryClip(
                from: transition.generator, file: position.file, event: "", depth: 0
            )
        else { return nil }
        found.stateName = transition.state.name
        if found.position == nil {
            found.position = BehaviorStatePosition(
                file: position.file, machine: position.machine, state: transition.state.stateId
            )
        }
        return found
    }

    /// The state's own transitions first, then the machine's wildcards.
    private func transition(
        on matches: (String) -> Bool, at position: BehaviorStatePosition
    ) -> EventTransition? {
        guard
            let events = graphEvents(position.file),
            let className = events.graph.className(at: position.machine),
            let machine = HKBClassRegistry.decoder(for: className)?(
                position.machine, events.graph
            ) as? HKBStateMachine
        else { return nil }
        let states = Self.states(of: machine, in: events.graph)
        let own = states.first { $0.stateId == position.state }?.transitions
        return Self.transitions(
            in: [own, machine.wildcardTransitions], states: states, graph: events.graph
        ).first { transition in
            events.names.indices.contains(transition.eventID)
                && events.names[transition.eventID].map { matches($0.lowercased()) } == true
        }
    }

    private static func triggers(
        of clip: HKBClipGenerator, in events: GraphEvents
    ) -> [BehaviorClipTriggerEvent] {
        guard
            let target = clip.triggers,
            let array = HKBClipTriggerArray.decode(at: target, in: events.graph)
        else { return [] }
        // Annotation triggers repeat the clip's own annotation track, which plays anyway.
        return array.triggers.filter { !$0.isAnnotation }.compactMap { trigger in
            guard
                events.names.indices.contains(trigger.event.id),
                let name = events.names[trigger.event.id]
            else { return nil }
            return BehaviorClipTriggerEvent(
                name: name, time: trigger.localTime, fromEnd: trigger.relativeToEndOfClip
            )
        }
    }
}
