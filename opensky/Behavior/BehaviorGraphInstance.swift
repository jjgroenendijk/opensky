// One running behavior graph (issue #187): the object that holds a decoded
// graph's variables, events, and per-node runtime state, and steps them.
//
// Nothing here is a singleton. An instance is built over a root generator and
// a `hkbBehaviorGraphData`, and two instances built over the same decoded file
// share nothing but the immutable decode — which is what item 14.7 (#190)
// needs when it puts a first-person graph beside the third-person one, and what
// makes the determinism test meaningful.
//
// The generator, clip, and modifier semantics live in the three satellite files
// beside this one. This file owns the instance's state, its update order, and
// the binding application every node's evaluation reads through.

import Foundation
import simd

/// Where a decoded object comes from. The engine answers from a parsed
/// packfile through `HKBClassRegistry`; a test answers from a dictionary of
/// structs it built in code, with no bytes anywhere.
nonisolated protocol BehaviorObjectSource {
    func object(at target: HKXPointerTarget) -> (any HKBClass)?
    func className(at target: HKXPointerTarget) -> String?
}

/// The packfile-backed source: decode on demand through the class registry.
nonisolated struct HKXBehaviorObjectSource: BehaviorObjectSource {
    let graph: HKXObjectGraph

    func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        HKBClassRegistry.decode(at: target, in: graph)
    }

    func className(at target: HKXPointerTarget) -> String? {
        graph.className(at: target)
    }
}

/// The runtime state of one node, keyed by where the node lives in the
/// packfile. A behavior graph is a DAG — a bone weight array or a transition
/// effect is shared by many parents — so state is per object, exactly as Havok
/// keys it, rather than per path through the tree.
nonisolated struct BehaviorNodeState: Equatable {
    /// True between the update that first reached this node and the update
    /// that stopped reaching it.
    var isActivated = false
    /// Seconds into the clip window, for a clip generator.
    var localTime: Float = 0
    /// `localTime` before the update in progress advanced it.
    var previousLocalTime: Float = 0
    /// How many times the clip has wrapped since activation, so an acyclic
    /// trigger can fire on the first cycle only.
    var cycleCount = 0
    /// Root bone at `previousLocalTime`, and at the two edges of the clip
    /// window, so a wrap can report the travel across the seam.
    var previousRootPose: HKABonePose?
    var windowStartRootPose: HKABonePose?
    var windowEndRootPose: HKABonePose?
    /// Seconds since activation, for a timer modifier.
    var elapsed: Float = 0
    /// True once a timer modifier has raised its alarm.
    var hasFiredAlarm = false
    /// Events counted, for the every-N-events modifier.
    var eventCount = 0
    /// Whether an event-driven modifier is currently running its wrapped one.
    var isModifierRunning = false
    /// True once the node has run its one-time activation setup, which is not
    /// the same as `isActivated`: activation marks the node reachable, seeding
    /// is what each class does with its first update.
    var hasSeeded = false
    /// `localTime` as a fraction of the clip window, for a clip generator. This
    /// is what clip synchronization reads and writes, and it is kept beside
    /// `localTime` rather than derived because the window length lives in the
    /// generator rather than in the state.
    var phase: Float = 0
}

/// What one update produced: the pose, the root travel kept beside it, and the
/// events the update saw. This is the contract items 14.4 through 14.6 consume.
nonisolated struct BehaviorUpdateResult: Equatable {
    /// Local TRS per skeleton bone. The root bone is left at its reference
    /// pose; its animated travel is in `rootMotion`.
    let bones: [HKABonePose]
    let rootMotion: BehaviorRootMotion
    /// Events visible during this update, in the order they were raised.
    let firedEvents: [BehaviorEvent]
    /// Seconds of graph time this instance has run.
    let time: Float
}

/// One graph instance: decoded objects in, poses and events out.
nonisolated final class BehaviorGraphInstance {
    /// How deep the generator walk may go before it stops and tallies. Vanilla
    /// player graphs nest well under this; a cycle would otherwise recurse
    /// without end, and a decoded graph is untrusted external input.
    static let maximumDepth = 64

    /// `hkbBehaviorGraph::m_name`, for reporting.
    let name: String?
    let skeleton: BehaviorSkeleton

    private let source: any BehaviorObjectSource
    private let clips: any BehaviorClipSource
    private let root: HKXPointerTarget?

    private(set) var variables: BehaviorVariableStore
    /// The event queue and the tally are internal rather than `private(set)`
    /// because the evaluation satellites beside this file mutate both, and an
    /// extension in another file cannot reach a private setter.
    var events: BehaviorEventQueue
    var tally: BehaviorTally
    private(set) var isActive = false
    private(set) var time: Float = 0

    /// Per-node runtime state, and which nodes the update in progress reached.
    var nodeStates: [HKXPointerTarget: BehaviorNodeState] = [:]
    var reachedThisUpdate: Set<HKXPointerTarget> = []

    /// Per-state-machine runtime state (issue #330). Deliberately not cleared
    /// by `deactivate()`: `m_startStateMode` 2 re-enters the state that was
    /// current when the machine stopped, so the id has to outlive the node.
    var machineStates: [HKXPointerTarget: BehaviorMachineState] = [:]
    /// Update index at which each event id was last active, so a transition's
    /// trigger and initiate intervals can be read as event windows.
    var eventLastSeen: [Int: Int] = [:]
    /// Parsed transition conditions, keyed by the condition object. The
    /// optional is stored so a string that will not parse is parsed once.
    var conditionCache: [HKXPointerTarget: BehaviorConditionExpression?] = [:]
    /// The playback phase a sync master or a synchronizing transition is
    /// imposing on the clips below the node being evaluated. `seedOnly` marks
    /// a transition's one-shot alignment apart from a blender's continuous one.
    var pendingClipPhase: (value: Float, seedOnly: Bool)?
    /// The state id a transition asks the next nested machine to start in,
    /// consumed by the first machine that enters below it.
    var pendingNestedStateId: Int?

    /// What every state machine the last update reached is doing, in walk
    /// order. This is the state path items 14.5 and 14.6 read, and what the
    /// real-data test asserts against the census state names.
    private(set) var activeStates: [BehaviorActiveState] = []
    /// The list being built by the update in progress.
    var activeStatesThisUpdate: [BehaviorActiveState] = []

    /// Decoded objects, cached so a DAG node shared by ten parents decodes
    /// once. The optional is stored so a miss is remembered as a miss.
    private var decoded: [HKXPointerTarget: (any HKBClass)?] = [:]

    init(
        name: String? = nil,
        root: HKXPointerTarget?,
        data: HKBBehaviorGraphData?,
        source: any BehaviorObjectSource,
        skeleton: BehaviorSkeleton,
        clips: any BehaviorClipSource = EmptyBehaviorClipSource(),
        tallyNameLimit: Int = BehaviorTally.defaultNameLimit
    ) {
        self.name = name
        self.root = root
        self.source = source
        self.skeleton = skeleton
        self.clips = clips
        variables = BehaviorVariableStore(data: data)
        events = BehaviorEventQueue(data: data)
        tally = BehaviorTally(nameLimit: tallyNameLimit)
    }

    /// Builds an instance over a decoded `hkbBehaviorGraph` in a parsed
    /// packfile — the engine-side entry point.
    convenience init(
        graph: HKBBehaviorGraph,
        in objectGraph: HKXObjectGraph,
        skeleton: BehaviorSkeleton,
        clips: any BehaviorClipSource = EmptyBehaviorClipSource(),
        tallyNameLimit: Int = BehaviorTally.defaultNameLimit
    ) {
        self.init(
            name: graph.name,
            root: graph.rootGenerator,
            data: graph.data,
            source: HKXBehaviorObjectSource(graph: objectGraph),
            skeleton: skeleton,
            clips: clips,
            tallyNameLimit: tallyNameLimit
        )
    }

    // MARK: - External input

    /// Sets a graph variable by name. False when the graph declares no such
    /// variable, which is how item 14.5 will learn that an engine input has no
    /// home in this graph rather than silently dropping it.
    @discardableResult
    func setVariable(_ value: BehaviorVariableValue, named name: String) -> Bool {
        variables.setValue(value, of: name)
    }

    func variable(named name: String) -> BehaviorVariableValue? {
        variables.value(of: name)
    }

    /// Raises an event by name, visible to the *next* update.
    @discardableResult
    func raiseEvent(named name: String, payload: String? = nil) -> Bool {
        events.raise(named: name, payload: payload)
    }

    // MARK: - Lifecycle

    /// Starts the graph. Idempotent; a second call on a running instance does
    /// nothing, because Havok's activation is a state and not an edge.
    func activate() {
        guard !isActive else { return }
        isActive = true
        time = 0
    }

    /// Stops the graph, deactivating every node that was running. Nodes are
    /// deactivated in packfile order so the events their deactivation raises
    /// come out in the same order on every run.
    func deactivate() {
        guard isActive else { return }
        deactivateNodes(Set(nodeStates.keys))
        nodeStates = [:]
        activeStates = []
        isActive = false
    }

    /// Advances the graph by one fixed timestep and returns the pose, the root
    /// travel, and the events the step saw.
    ///
    /// The order is fixed and total:
    ///
    /// 1. Events raised since the last update become the active set. Nothing
    ///    raised during this update is visible to it.
    /// 2. The generator tree is walked depth first from the root, children in
    ///    the order the class declares them. A node's bindings are applied
    ///    immediately before it is evaluated, so every node sees the same
    ///    variable values.
    /// 3. Nodes reached last update but not this one are deactivated, in
    ///    packfile order.
    /// 4. The active event set is closed and returned.
    @discardableResult
    func update(deltaTime: Float) -> BehaviorUpdateResult {
        if !isActive {
            activate()
        }
        let step = deltaTime.isFinite ? max(deltaTime, 0) : 0
        tally.noteUpdate()
        for event in events.beginUpdate() {
            eventLastSeen[event.id] = tally.updatesRun
        }
        time += step

        let previouslyReached = reachedThisUpdate
        reachedThisUpdate = []
        activeStatesThisUpdate = []
        pendingClipPhase = nil
        pendingNestedStateId = nil
        let pose = evaluateGenerator(at: root, depth: 0, deltaTime: step)
        activeStates = activeStatesThisUpdate
        deactivateNodes(previouslyReached.subtracting(reachedThisUpdate))

        var bones = pose.bones
        if
            bones.indices.contains(skeleton.rootBoneIndex),
            skeleton.referencePose.indices.contains(skeleton.rootBoneIndex)
        {
            bones[skeleton.rootBoneIndex] = skeleton.referencePose[skeleton.rootBoneIndex]
        }
        return BehaviorUpdateResult(
            bones: bones,
            rootMotion: pose.rootMotion,
            firedEvents: events.endUpdate(),
            time: time
        )
    }

    /// Runs the deactivation hooks of `targets` and forgets their state.
    private func deactivateNodes(_ targets: Set<HKXPointerTarget>) {
        for target in targets.sorted(by: Self.isOrderedBefore) {
            if let object = object(at: target) {
                noteDeactivation(of: object, at: target)
            }
            nodeStates[target] = nil
        }
        reachedThisUpdate.subtract(targets)
    }

    /// Packfile order: section first, then offset. Only used to make the
    /// deactivation sweep deterministic.
    static func isOrderedBefore(_ lhs: HKXPointerTarget, _ rhs: HKXPointerTarget) -> Bool {
        lhs.sectionIndex == rhs.sectionIndex
            ? lhs.dataOffset < rhs.dataOffset
            : lhs.sectionIndex < rhs.sectionIndex
    }

    // MARK: - Object access

    /// The decoded object at `target`, cached. A location with no registered
    /// class, or a class with no decoder, comes back nil and is tallied once.
    func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        if let cached = decoded[target] {
            return cached
        }
        let value = source.object(at: target)
        decoded[target] = value
        if value == nil {
            tally.noteUndecodableObject(source.className(at: target))
        }
        return value
    }

    /// The decoded object at `target` as `Value`, or nil.
    func object<Value: HKBClass>(at target: HKXPointerTarget, as _: Value.Type) -> Value? {
        object(at: target) as? Value
    }

    /// The clip a generator names, or nil with one tally entry.
    func clip(named name: String?, bindingIndex: Int) -> (any BehaviorClip)? {
        guard let found = clips.clip(named: name, bindingIndex: bindingIndex) else {
            tally.noteUnresolvedClip(name)
            return nil
        }
        return found
    }

    /// Marks `target` as reached this update, activating it on the first reach.
    /// Returns its state, which callers mutate through `nodeStates`.
    @discardableResult
    func markReached(_ target: HKXPointerTarget) -> BehaviorNodeState {
        reachedThisUpdate.insert(target)
        if let existing = nodeStates[target], existing.isActivated {
            return existing
        }
        var state = BehaviorNodeState()
        state.isActivated = true
        nodeStates[target] = state
        return state
    }

    func state(of target: HKXPointerTarget) -> BehaviorNodeState {
        nodeStates[target] ?? BehaviorNodeState()
    }

    // MARK: - Bindings

    /// The variable values bound onto `object` right now, keyed by the member
    /// path the binding names. Recomputed per evaluation rather than cached,
    /// because a binding must see a variable another node wrote this update.
    func boundValues(of object: any HKBClass) -> [String: BehaviorVariableValue] {
        guard
            let setTarget = object.references
                .first(where: { $0.field == "m_variableBindingSet" })?.target,
            let bindingSet = self.object(at: setTarget, as: HKBVariableBindingSet.self)
        else {
            return [:]
        }
        var values: [String: BehaviorVariableValue] = [:]
        for binding in bindingSet.bindings {
            guard let value = resolve(binding) else { continue }
            guard let path = binding.memberPath, !path.isEmpty else {
                // An empty path binds the object wholesale, which only Havok's
                // pointer variables can do; nothing in this evaluator can act
                // on one, so it is recorded rather than guessed at.
                tally.noteUnappliedBinding(binding.memberPath)
                continue
            }
            tally.noteBinding(path)
            values[Self.normalizedMemberPath(path)] = value
        }
        return values
    }

    /// Binding member paths as the vanilla files spell them carry no `m_`
    /// prefix — the probe over the install reports `blendParameter`,
    /// `selectedGeneratorIndex`, `startStateId` — while the decoders name their
    /// fields after the Havok members, which do. Both spellings normalize to
    /// the unprefixed one so a lookup written either way resolves.
    static func normalizedMemberPath(_ path: String) -> String {
        path.hasPrefix("m_") ? String(path.dropFirst(2)) : path
    }

    /// The current value of one binding, or nil with a tally entry when it
    /// cannot be applied.
    private func resolve(_ binding: HKBVariableBinding) -> BehaviorVariableValue? {
        guard binding.bindingType == 0 else {
            // Character properties come from `hkbCharacterData`, which this
            // instance does not hold; item 14.5 supplies them.
            tally.noteUnappliedBinding(binding.memberPath)
            return nil
        }
        guard let value = variables.value(at: binding.variableIndex) else {
            tally.noteUnappliedBinding(binding.memberPath)
            return nil
        }
        guard binding.bitIndex >= 0 else { return value }
        // A bit-addressed binding reads one bit of a packed word variable.
        let bit = binding.bitIndex
        guard bit < 32 else {
            tally.noteUnappliedBinding(binding.memberPath)
            return nil
        }
        return .bool(value.intValue & (1 << bit) != 0)
    }

    /// True when `object`'s binding set names a binding that disables it.
    func isDisabled(_ object: any HKBClass) -> Bool {
        guard
            let setTarget = object.references
                .first(where: { $0.field == "m_variableBindingSet" })?.target,
            let bindingSet = self.object(at: setTarget, as: HKBVariableBindingSet.self),
            bindingSet.bindings.indices.contains(bindingSet.indexOfBindingToEnable),
            let value = resolve(bindingSet.bindings[bindingSet.indexOfBindingToEnable])
        else {
            return false
        }
        return !value.boolValue
    }
}

nonisolated extension [String: BehaviorVariableValue] {
    /// The bound float for `path`, or `fallback` when nothing is bound there.
    /// `path` may be spelled with or without the Havok `m_` prefix.
    func float(_ path: String, or fallback: Float) -> Float {
        value(path)?.realValue ?? fallback
    }

    /// The bound integer for `path`, or `fallback`.
    func int(_ path: String, or fallback: Int) -> Int {
        value(path)?.intValue ?? fallback
    }

    /// The bound bool for `path`, or `fallback`.
    func bool(_ path: String, or fallback: Bool) -> Bool {
        value(path)?.boolValue ?? fallback
    }

    private func value(_ path: String) -> BehaviorVariableValue? {
        self[BehaviorGraphInstance.normalizedMemberPath(path)]
    }
}
