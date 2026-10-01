// Resolves `hkbBehaviorReferenceGenerator`: each referenced file (`mt_behavior.hkx`)
// becomes its own instance with the parent's skeleton and clip source. Variables pass
// down by name; events pass both ways one update late. Only the child's `pending`
// queue goes up, so events do not echo forever. A reference reached twice runs once,
// and an ancestor cycle is refused by name. See docs/engine/behavior-clips.md.

import Foundation
import OpenSkyFormatsAnimation

/// Where a named behavior file comes from. The engine answers by loading it out
/// of the install; a test answers from a table it built in code.
nonisolated public protocol BehaviorReferenceSource {
    /// The graph `name` refers to, built over `skeleton` and `clips`, or nil
    /// when this source cannot supply it.
    func behavior(
        named name: String,
        skeleton: BehaviorSkeleton,
        clips: any BehaviorClipSource
    ) -> BehaviorGraphInstance?
}

nonisolated extension BehaviorGraphInstance {
    /// Evaluates one behavior reference, or the reference pose with a tally
    /// entry when the name cannot be resolved.
    public func evaluateBehaviorReference(
        _ generator: HKBBehaviorReferenceGenerator,
        deltaTime: Float
    ) -> BehaviorPose {
        guard
            let name = generator.behaviorName,
            let child = referencedGraph(named: name)
        else {
            tally.note(.unresolvedBehaviorReference)
            return skeleton.restPose
        }
        if let memo = referencedResults[name] {
            return BehaviorPose(bones: memo.bones, rootMotion: memo.rootMotion)
        }
        let key = Self.referenceKey(name)
        pushVariables(into: child)
        pushEvents(into: child, key: key)
        let result = child.update(deltaTime: deltaTime)
        referencedResults[name] = result
        pullEvents(from: child, key: key)
        activeStatesThisUpdate += child.activeStates
        return BehaviorPose(bones: result.bones, rootMotion: result.rootMotion)
    }

    /// The child instance for `name`, loaded once. A miss is remembered as a
    /// miss so a graph naming an absent file does not retry the load every
    /// frame.
    private func referencedGraph(named name: String) -> BehaviorGraphInstance? {
        let key = Self.referenceKey(name)
        if let cached = referencedGraphs[key] {
            return cached
        }
        guard let references, !referenceAncestry.contains(key) else {
            referencedGraphs[key] = BehaviorGraphInstance?.none
            return nil
        }
        let child = references.behavior(named: name, skeleton: skeleton, clips: clipSource)
        child?.references = references
        child?.referenceAncestry = referenceAncestry.union([key])
        referencedGraphs[key] = child
        if child == nil {
            tally.note(.unresolvedBehaviorReference)
        }
        return child
    }

    /// Copies every variable the child declares and the parent also declares.
    /// Names the child alone declares keep whatever its own file initialized
    /// them to, which is what a sub-behavior's private state is.
    private func pushVariables(into child: BehaviorGraphInstance) {
        for name in child.variables.names {
            guard let name, let value = variables.value(of: name) else { continue }
            child.setVariable(value, named: name)
        }
    }

    /// Raises the parent's currently active events on the child, minus the ones
    /// this same child raised on the update the parent pulled from. Those are
    /// already queued on the child by its own raise, so pushing them back would
    /// deliver one event to the child twice.
    private func pushEvents(into child: BehaviorGraphInstance, key: String) {
        let echoed = pulledEventNames[key] ?? []
        for event in events.active {
            guard let name = event.name, !echoed.contains(name) else { continue }
            child.raiseEvent(named: name, payload: event.payload)
        }
    }

    /// Raises what the child's own nodes raised during its update back on the
    /// parent, visible to the parent's next update.
    ///
    /// The child's `pending` queue, not the `firedEvents` its update returned:
    /// see the echo note in this file's header comment.
    private func pullEvents(from child: BehaviorGraphInstance, key: String) {
        var raised: Set<String> = []
        for event in child.events.pending {
            guard let name = event.name else { continue }
            if events.raise(named: name, payload: event.payload) {
                raised.insert(name)
            }
        }
        pulledEventNames[key] = raised
    }

    /// Behavior names are compared case-insensitively on the file name alone,
    /// because a reference spells the name the project's `m_behaviorFilenames`
    /// spells it and those carry mixed case and mixed separators.
    public static func referenceKey(_ name: String) -> String {
        let file = name.replacingOccurrences(of: "/", with: "\\")
            .split(separator: "\\").last.map(String.init) ?? name
        return file.lowercased()
    }
}
