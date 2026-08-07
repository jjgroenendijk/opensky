// Resolving `hkbBehaviorReferenceGenerator` (issue #189).
//
// Skyrim's player graph is not one file. `0_master.hkx` is a shell: its jump,
// movement, combat, and magic branches are `hkbBehaviorReferenceGenerator`
// nodes that name another behavior file — `mt_behavior.hkx`, `1hm_behavior.hkx`
// and the rest — rather than pointing at a subtree. Items 14.3 and 14.4 left
// those unresolved and tallied, which was correct then: with only `0_master`
// loaded, the graph could enter its jump states and nothing else. The
// locomotion states item 14.6 has to reach all live behind one of these
// references, so this is where they get followed.
//
// How a reference is evaluated, and why:
//
// * The referenced file becomes its own `BehaviorGraphInstance`, over its own
//   decode, with the parent's skeleton and the parent's clip source. It has to
//   be its own instance because it has its own variables, its own events, and
//   its own per-node state, exactly as Havok's `hkbBehaviorGraph` does.
// * Variables cross by name, parent to child, before every child update. That
//   is what Havok's variable mapping does in effect: the sub-behaviors declare
//   the same authored names (`Speed`, `Direction`, `bIsSprinting`) and read the
//   values the character wrote on the root graph.
// * Events cross both ways by name: the parent's active set is raised on the
//   child before its update, and what the child *raised during* its update is
//   raised back on the parent for the parent's next update. A transition in
//   `mt_behavior` that `0_master` needs to see therefore arrives one update
//   later, which is the same one-update latency every event in this evaluator
//   already has.
// * What comes back up is the child's `pending` queue, not the `firedEvents`
//   its update returned, and each direction refuses what the other just sent.
//   `firedEvents` is the child's *active* set, which by construction already
//   holds everything the parent pushed in on the previous update: raising that
//   back on the parent made every crossing event echo between the two graphs
//   forever, one copy per update each way. The player graph therefore re-fired
//   `moveStart` and `IdleStop` on every single update, which saturated the
//   bounded drain in `LocomotionGraphEventQueue` and pushed the real footstep
//   tags out of it before an audio frame could read them (issues #385, #394).
//   `pending` holds exactly what the child's own nodes raised, and skipping the
//   names just pulled from a child when pushing back into it keeps a child's
//   own event from being delivered to it a second time.
// * A reference reached twice in one parent update is evaluated once. Without
//   the memo the child would advance its clock once per reach and run fast.
//
// Cycles are impossible to rule out in modded data, so a child that references
// its own ancestor is refused by name rather than by recursion depth.
//
// See docs/engine/behavior-runtime.md.

import Foundation

/// Where a named behavior file comes from. The engine answers by loading it out
/// of the install; a test answers from a table it built in code.
nonisolated protocol BehaviorReferenceSource {
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
    func evaluateBehaviorReference(
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
    static func referenceKey(_ name: String) -> String {
        let file = name.replacingOccurrences(of: "/", with: "\\")
            .split(separator: "\\").last.map(String.init) ?? name
        return file.lowercased()
    }
}
