// Which clip annotations the behaviour graphs of their own project wait for. The
// graph raises a declared annotation as an event, so a graph that listens acts on it
// without the engine. `openskycli gaps` counts such an event as done (docs/tools/gaps.md).

import Foundation

nonisolated public enum HKBEventListeners {
    /// The event ids the object waits for: a transition and its trigger and initiate
    /// windows, a state machine's own events, and the nodes that switch or count on one.
    public static func eventIDs(of object: any HKBClass) -> [Int] {
        switch object {
        case let array as HKBStateMachineTransitionInfoArray:
            array.transitions.flatMap { transition in
                [transition.eventId]
                    + intervalIDs(transition.triggerInterval)
                    + intervalIDs(transition.initiateInterval)
            }
        case let machine as HKBStateMachine:
            [
                machine.returnToPreviousStateEventId, machine.randomTransitionEventId,
                machine.transitionToNextHigherStateEventId,
                machine.transitionToNextLowerStateEventId
            ]
        case let modifier as HKBEventDrivenModifier:
            [modifier.activateEventId, modifier.deactivateEventId]
        case let generator as HKBPoseMatchingGenerator:
            [generator.startPlayingEventId, generator.startMatchingEventId]
        case let modifier as BSEventEveryNEventsModifier:
            [modifier.eventToCheckFor.id]
        case let generator as BSCyclicBlendTransitionGenerator:
            [generator.eventToFreezeBlendValue.id, generator.eventToCrossBlend.id]
        default:
            []
        }
    }

    private static func intervalIDs(_ interval: HKBStateMachineTimeInterval) -> [Int] {
        [interval.enterEventId, interval.exitEventId]
    }
}

/// Clip annotations and graph listeners, grouped by project. A project is the folder
/// above `animations` or `behaviors`, such as `meshes\actors\canine\` for both
/// `canine\animations` and `canine\behaviors wolf`.
nonisolated public struct HKXAnnotationHearing: Sendable {
    /// Project -> annotation texts its clips carry, in lower case.
    private var annotations: [String: Set<String>] = [:]
    /// Project -> event names its graphs wait for, in lower case.
    private var listened: [String: Set<String>] = [:]

    public init() {}

    public mutating func addAnnotation(_ text: String, clipPath: String) {
        annotations[Self.project(of: clipPath), default: []].insert(text.lowercased())
    }

    public mutating func addListened(_ names: [String], graphPath: String) {
        listened[Self.project(of: graphPath), default: []]
            .formUnion(names.map { $0.lowercased() })
    }

    /// The folded events (`HKXGapCensus.event`), in lower case, that a graph of the
    /// clip's own project waits for. A paired clip has its own folder, so no graph hears it.
    public func heardEvents() -> Set<String> {
        var heard = Set<String>()
        for (project, texts) in annotations {
            guard let names = listened[project] else { continue }
            for text in texts.intersection(names) {
                heard.insert(HKXGapCensus.event(text).lowercased())
            }
        }
        return heard
    }

    static func project(of path: String) -> String {
        let parts = path.lowercased().split(separator: "\\", omittingEmptySubsequences: false)
        let cut = parts.firstIndex { $0 == "animations" || $0.hasPrefix("behaviors") }
            ?? max(parts.count - 1, 0)
        return parts[..<cut].map { $0 + "\\" }.joined()
    }
}
