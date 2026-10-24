// One running behavior graph: the decoded graph's variables, events, and
// per-node runtime state. Two instances over one decoded file share only the
// immutable decode. The generator, clip, and modifier semantics live in the
// satellite files; this file owns the state and the update order.

import Foundation
import OpenSkyFormatsAnimation
import simd

/// Where a decoded object comes from. The engine answers from a parsed
/// packfile through `HKBClassRegistry`; a test answers from a dictionary of
/// structs it built in code, with no bytes anywhere.
nonisolated public protocol BehaviorObjectSource {
    func object(at target: HKXPointerTarget) -> (any HKBClass)?
    func className(at target: HKXPointerTarget) -> String?
}

/// The packfile-backed source: decode on demand through the class registry.
nonisolated public struct HKXBehaviorObjectSource: BehaviorObjectSource, Sendable {
    public let graph: HKXObjectGraph

    public func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        HKBClassRegistry.decode(at: target, in: graph)
    }

    public func className(at target: HKXPointerTarget) -> String? {
        graph.className(at: target)
    }
}

/// The runtime state of one node, keyed by where the node lives in the
/// packfile. A behavior graph is a DAG — a bone weight array or a transition
/// effect is shared by many parents — so state is per object, exactly as Havok
/// keys it, rather than per path through the tree.
nonisolated public struct BehaviorNodeState: Equatable, Sendable {
    /// True between the update that first reached this node and the update
    /// that stopped reaching it.
    public var isActivated = false
    /// Seconds into the clip window, for a clip generator.
    public var localTime: Float = 0
    /// `localTime` before the update in progress advanced it.
    public var previousLocalTime: Float = 0
    /// How many times the clip has wrapped since activation, so an acyclic
    /// trigger can fire on the first cycle only.
    public var cycleCount = 0
    /// Root bone at `previousLocalTime`, and at the two edges of the clip
    /// window, so a wrap can report the travel across the seam.
    public var previousRootPose: HKABonePose?
    public var windowStartRootPose: HKABonePose?
    public var windowEndRootPose: HKABonePose?
    /// Seconds since activation, for a timer modifier.
    public var elapsed: Float = 0
    /// True once a timer modifier has raised its alarm.
    public var hasFiredAlarm = false
    /// Events counted, for the every-N-events modifier.
    public var eventCount = 0
    /// Whether an event-driven modifier is currently running its wrapped one.
    public var isModifierRunning = false
    /// True once the node has run its one-time activation setup, which is not
    /// the same as `isActivated`: activation marks the node reachable, seeding
    /// is what each class does with its first update.
    public var hasSeeded = false
    /// `localTime` as a fraction of the clip window, for a clip generator. This
    /// is what clip synchronization reads and writes, and it is kept beside
    /// `localTime` rather than derived because the window length lives in the
    /// generator rather than in the state.
    public var phase: Float = 0
    /// PID error terms, for a damping modifier. A scalar uses `x`.
    public var errorSum = SIMD4<Float>()
    public var previousError = SIMD4<Float>()
    /// Last seen truth per slot, for edge detectors and expression event modes.
    public var flags: [Bool] = []
    /// Per slot: true once the slot has sent its event since activation.
    public var sentFlags: [Bool] = []
    /// Per-bone or per-axis blend weights, for the aiming and IK modifiers.
    public var weights: [Float] = []
    /// The band an events-from-range modifier was in last update.
    public var rangeIndex: Int?
    /// Events to count before the next send, for the every-N-events modifier.
    public var eventThreshold = 0
    /// The pose a cyclic blend crossfades away from, while it does.
    public var crossBlendSource: BehaviorPose?
}

/// What one update produced: the pose, the root travel kept beside it, and the
/// events the update saw. This is the contract items 14.4 through 14.6 consume.
nonisolated public struct BehaviorUpdateResult: Equatable, Sendable {
    /// Local TRS per skeleton bone. The root bone is left at its reference
    /// pose; its animated travel is in `rootMotion`.
    public let bones: [HKABonePose]
    public let rootMotion: BehaviorRootMotion
    /// Events visible during this update, in the order they were raised.
    public let firedEvents: [BehaviorEvent]
    /// Clip annotations and child graph events this graph declares no event for. The
    /// engine still acts on them, such as `SoundPlay.<editor ID>` in any clip.
    public let unboundEvents: [String]
}

/// One graph instance: decoded objects in, poses and events out.
nonisolated public final class BehaviorGraphInstance {
    /// How deep the generator walk may go before it stops and tallies. Vanilla
    /// player graphs nest well under this; a cycle would otherwise recurse
    /// without end, and a decoded graph is untrusted external input.
    public static let maximumDepth = 64

    public let skeleton: BehaviorSkeleton

    private let source: any BehaviorObjectSource
    private let clips: any BehaviorClipSource
    public let root: HKXPointerTarget?

    /// Where `hkbBehaviorReferenceGenerator` names resolve. Nil leaves every
    /// reference unresolved and tallied.
    public var references: (any BehaviorReferenceSource)?
    /// Child instances by reference key, built on first reach. The optional is
    /// stored so a name that will not resolve is looked up once.
    public var referencedGraphs: [String: BehaviorGraphInstance?] = [:]
    /// What each referenced graph produced during the update in progress, so a
    /// reference reached twice advances its child's clock once.
    public var referencedResults: [String: BehaviorUpdateResult] = [:]
    /// Event names pulled up out of each referenced graph on the last update
    /// that reached it, so pushing the parent's active set back down does not
    /// hand a child its own event a second time (see
    /// BehaviorReferenceResolution.swift).
    public var pulledEventNames: [String: Set<String>] = [:]
    /// Reference keys of this instance and everything above it, so a modded
    /// graph that references its own ancestor is refused by name rather than
    /// recursed into.
    public var referenceAncestry: Set<String> = []

    /// The clip source, shared with any graph this one references.
    public var clipSource: any BehaviorClipSource {
        clips
    }

    public private(set) var variables: BehaviorVariableStore
    /// The event queue and the tally are internal rather than `private(set)`
    /// because the evaluation satellites beside this file mutate both, and an
    /// extension in another file cannot reach a private setter.
    public var events: BehaviorEventQueue
    public var tally: BehaviorTally
    public private(set) var isActive = false
    public private(set) var time: Float = 0

    /// Per-node runtime state, and which nodes the update in progress reached.
    public var nodeStates: [HKXPointerTarget: BehaviorNodeState] = [:]
    public var reachedThisUpdate: Set<HKXPointerTarget> = []

    /// Per-state-machine runtime state. Not cleared by `deactivate()`:
    /// `m_startStateMode` 2 re-enters the state that was current when it stopped.
    public var machineStates: [HKXPointerTarget: BehaviorMachineState] = [:]
    /// Update index at which each event id was last active, so a transition's
    /// trigger and initiate intervals can be read as event windows.
    public var eventLastSeen: [Int: Int] = [:]
    /// Parsed transition conditions, keyed by the condition object. The
    /// optional is stored so a string that will not parse is parsed once.
    public var conditionCache: [HKXPointerTarget: BehaviorConditionExpression?] = [:]
    /// The playback phase a sync master or a synchronizing transition is
    /// imposing on the clips below the node being evaluated. `seedOnly` marks
    /// a transition's one-shot alignment apart from a blender's continuous one.
    public var pendingClipPhase: (value: Float, seedOnly: Bool)?
    /// The start states a transition hands to the machines below it, outermost
    /// first. Each machine that enters below it takes the first one.
    public var pendingNestedStateIds: [Int] = []
    /// Global wildcard routes per machine, built on first reach.
    public var globalWildcardRouteCache: [HKXPointerTarget: [BehaviorGlobalWildcardRoute]] = [:]

    /// Seconds the animated-to-simulated blend takes, from the last evaluated
    /// `hkbRigidBodyRagdollControlsModifier`. Nil until one has run. Internal, because
    /// the modifier that writes it is an extension in another file.
    public var ragdollBlendDuration: Float?
    /// The `hkbPoweredRagdollControlsModifier` the last update ran, or nil.
    public var poweredRagdollControls: HKBPoweredRagdollControlsModifier?
    /// The event the last update's `BSRagdollContactListenerModifier` raises on contact.
    public var ragdollContactEvent: String?
    /// Where the character stands and what ground it stands on.
    public var characterContext = BehaviorCharacterContext()
    /// The physics hand-offs the last update's modifiers asked for.
    public var physicsRequests = BehaviorPhysicsRequests()
    /// Variable indexes a node wrote back this update, so a deactivating node
    /// does not overwrite what a newly active one just wrote.
    public var variablesWrittenThisUpdate: Set<Int> = []
    /// Parsed `hkbEvaluateExpressionModifier` statements per expression array.
    public var statementCache: [HKXPointerTarget: [BehaviorExpressionStatement?]] = [:]
    /// Mean ankle correction of the last foot IK solve, model space.
    public var footIkError = SIMD3<Float>()
    /// The pose each cyclic blend generator produced last, so a crossfade can start from it.
    public var cyclicLastPoses: [HKXPointerTarget: BehaviorPose] = [:]
    /// The source of every random choice the graph makes. Seeded the same for
    /// every instance, so two runs with the same input stay identical.
    public var random = BehaviorRandom()

    /// What every state machine the last update reached is doing, in walk
    /// order. This is the state path items 14.5 and 14.6 read, and what the
    /// real-data test asserts against the census state names.
    public private(set) var activeStates: [BehaviorActiveState] = []
    /// The list being built by the update in progress.
    public var activeStatesThisUpdate: [BehaviorActiveState] = []

    /// What the update in progress raised that this graph declares no event for.
    public var unboundEvents: [String] = []
    /// True when the update in progress reached a clip that is still loading.
    public var isWaitingForClip = false
    /// The sync prefix of the synchronized clip being evaluated, nil outside one.
    var syncTrackPrefix: String?
    /// This actor's views of the paired clips it played, by prefix and clip name.
    var pairedClips: [String: PairedBehaviorClip] = [:]
    /// The bones of the last update that had every clip it reached, held while
    /// a clip loads so the character keeps its pose instead of snapping to rest.
    private var lastCompleteBones: [HKABonePose]?

    /// Compiled nodes, cached so a DAG node shared by ten parents decodes
    /// once. The optional is stored so a miss is remembered as a miss.
    private var compiled: [HKXPointerTarget: BehaviorCompiledNode?] = [:]

    public init(
        root: HKXPointerTarget?,
        data: HKBBehaviorGraphData?,
        source: any BehaviorObjectSource,
        skeleton: BehaviorSkeleton,
        clips: any BehaviorClipSource = EmptyBehaviorClipSource(),
        tallyNameLimit: Int = BehaviorTally.defaultNameLimit
    ) {
        self.root = root
        self.source = source
        self.skeleton = skeleton
        self.clips = clips
        variables = BehaviorVariableStore(data: data)
        events = BehaviorEventQueue(data: data)
        tally = BehaviorTally(nameLimit: tallyNameLimit)
    }

    /// Builds an instance over a decoded `hkbBehaviorGraph` in a parsed
    /// packfile — the engine-side entry point. Instances over one file share `objects`.
    public convenience init(
        graph: HKBBehaviorGraph,
        in objectGraph: HKXObjectGraph,
        skeleton: BehaviorSkeleton,
        clips: any BehaviorClipSource = EmptyBehaviorClipSource(),
        objects: SharedBehaviorObjectSource? = nil,
        tallyNameLimit: Int = BehaviorTally.defaultNameLimit
    ) {
        self.init(
            root: graph.rootGenerator,
            data: graph.data,
            source: objects ?? HKXBehaviorObjectSource(graph: objectGraph),
            skeleton: skeleton,
            clips: clips,
            tallyNameLimit: tallyNameLimit
        )
    }

    // MARK: - Lifecycle

    /// Starts the graph. Idempotent; a second call on a running instance does
    /// nothing, because Havok's activation is a state and not an edge.
    public func activate() {
        guard !isActive else { return }
        isActive = true
        time = 0
    }

    /// Stops the graph, deactivating every node that was running. Nodes are
    /// deactivated in packfile order so the events their deactivation raises
    /// come out in the same order on every run.
    public func deactivate() {
        guard isActive else { return }
        deactivateNodes(Set(nodeStates.keys))
        nodeStates = [:]
        activeStates = []
        pulledEventNames = [:]
        isActive = false
    }

    /// Advances the graph by one fixed timestep and returns the pose, root travel,
    /// and events. Order: queued events become active; the tree is walked depth
    /// first, bindings applied just before each node; nodes not reached are
    /// deactivated; the event set is returned.
    @discardableResult
    public func update(deltaTime: Float) -> BehaviorUpdateResult {
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
        referencedResults = [:]
        pendingClipPhase = nil
        unboundEvents = []
        pendingNestedStateIds = []
        isWaitingForClip = false
        poweredRagdollControls = nil
        ragdollContactEvent = nil
        physicsRequests = BehaviorPhysicsRequests()
        variablesWrittenThisUpdate = []
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
        if isWaitingForClip, let held = lastCompleteBones {
            return BehaviorUpdateResult(
                bones: held, rootMotion: .identity, firedEvents: events.endUpdate(),
                unboundEvents: unboundEvents
            )
        }
        lastCompleteBones = bones
        return BehaviorUpdateResult(
            bones: bones,
            rootMotion: pose.rootMotion,
            firedEvents: events.endUpdate(),
            unboundEvents: unboundEvents
        )
    }

    /// Runs the deactivation hooks of `targets` and forgets their state.
    func deactivateNodes(_ targets: Set<HKXPointerTarget>) {
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
    public static func isOrderedBefore(_ lhs: HKXPointerTarget, _ rhs: HKXPointerTarget) -> Bool {
        lhs.sectionIndex == rhs.sectionIndex
            ? lhs.dataOffset < rhs.dataOffset
            : lhs.sectionIndex < rhs.sectionIndex
    }

    // MARK: - Object access

    /// The decoded object at `target`, cached. A location with no registered
    /// class, or a class with no decoder, comes back nil and is tallied once.
    public func object(at target: HKXPointerTarget) -> (any HKBClass)? {
        compiledNode(at: target)?.object
    }

    /// The node at `target` with its children and bindings resolved, built once.
    public func compiledNode(at target: HKXPointerTarget) -> BehaviorCompiledNode? {
        if let cached = compiled[target] {
            return cached
        }
        guard let object = source.object(at: target) else {
            compiled[target] = BehaviorCompiledNode?.none
            tally.noteUndecodableObject(source.className(at: target))
            return nil
        }
        let references = object.references
        let bindingSet = references
            .first { $0.field == "m_variableBindingSet" }
            .flatMap { self.object(at: $0.target, as: HKBVariableBindingSet.self) }
        let node = BehaviorCompiledNode(
            object: object,
            children: references.map(\.target),
            bindings: bindingSet.map(BehaviorCompiledBindings.init)
        )
        compiled[target] = node
        return node
    }

    /// The decoded object at `target` as `Value`, or nil.
    public func object<Value: HKBClass>(at target: HKXPointerTarget, as _: Value.Type) -> Value? {
        object(at: target) as? Value
    }

    /// The clip a generator names, or nil: a wait while it loads, else one tally entry.
    public func clip(named name: String?, bindingIndex: Int) -> (any BehaviorClip)? {
        guard let found = clips.clip(named: name, bindingIndex: bindingIndex) else {
            if clips.isLoading(named: name, bindingIndex: bindingIndex) {
                isWaitingForClip = true
            } else {
                tally.noteUnresolvedClip(name)
            }
            return nil
        }
        return pairedView(of: found, named: name)
    }

    /// Marks `target` as reached this update, activating it on the first reach.
    /// Returns its state, which callers mutate through `nodeStates`.
    @discardableResult
    public func markReached(_ target: HKXPointerTarget) -> BehaviorNodeState {
        reachedThisUpdate.insert(target)
        if let existing = nodeStates[target], existing.isActivated {
            return existing
        }
        var state = BehaviorNodeState()
        state.isActivated = true
        nodeStates[target] = state
        return state
    }

    // MARK: - Bindings

    /// The variable values bound onto `object` right now, keyed by the member
    /// path the binding names. Recomputed per evaluation rather than cached,
    /// because a binding must see a variable another node wrote this update.
    public func boundValues(of node: BehaviorCompiledNode) -> [String: BehaviorVariableValue] {
        guard let compiled = node.bindings else { return [:] }
        var values: [String: BehaviorVariableValue] = [:]
        // `isDisabled` already reads the enable binding.
        for index in compiled.bindings.indices where index != compiled.enableIndex {
            let binding = compiled.bindings[index]
            guard let value = resolve(binding) else { continue }
            guard let path = compiled.paths[index], let memberPath = binding.memberPath else {
                // An empty path binds the object wholesale, which only Havok's
                // pointer variables can do; nothing in this evaluator can act
                // on one, so it is recorded rather than guessed at.
                tally.noteUnappliedBinding(binding.memberPath)
                continue
            }
            tally.noteBinding(memberPath)
            values[path] = value
        }
        return values
    }

    /// Binding member paths as the vanilla files spell them carry no `m_`
    /// prefix — the probe over the install reports `blendParameter`,
    /// `selectedGeneratorIndex`, `startStateId` — while the decoders name their
    /// fields after the Havok members, which do. Both spellings normalize to
    /// the unprefixed one so a lookup written either way resolves.
    public static func normalizedMemberPath(_ path: String) -> String {
        path.hasPrefix("m_") ? String(path.dropFirst(2)) : path
    }

    /// The current value of one binding, or nil with a tally entry when it
    /// cannot be applied.
    private func resolve(_ binding: HKBVariableBinding) -> BehaviorVariableValue? {
        guard binding.bindingType == 0 else {
            // Character properties come from `hkbCharacterData`, which this instance
            // does not hold; the locomotion bridge supplies them.
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

    /// True when `node`'s binding set names a binding that disables it.
    public func isDisabled(_ node: BehaviorCompiledNode) -> Bool {
        guard
            let compiled = node.bindings,
            let index = compiled.enableIndex,
            let value = resolve(compiled.bindings[index])
        else {
            return false
        }
        return !value.boolValue
    }
}

nonisolated extension [String: BehaviorVariableValue] {
    /// The bound float for `path`, or `fallback` when nothing is bound there.
    /// `path` may be spelled with or without the Havok `m_` prefix.
    public func float(_ path: String, or fallback: Float) -> Float {
        value(path)?.realValue ?? fallback
    }

    /// The bound integer for `path`, or `fallback`.
    public func int(_ path: String, or fallback: Int) -> Int {
        value(path)?.intValue ?? fallback
    }

    private func value(_ path: String) -> BehaviorVariableValue? {
        self[BehaviorGraphInstance.normalizedMemberPath(path)]
    }
}

nonisolated extension BehaviorGraphInstance {
    // MARK: - External input

    /// Sets a graph variable by name. False when the graph declares no such variable, so a
    /// caller learns an input has no home instead of losing it silently.
    @discardableResult
    public func setVariable(_ value: BehaviorVariableValue, named name: String) -> Bool {
        variables.setValue(value, of: name)
    }

    public func variable(named name: String) -> BehaviorVariableValue? {
        variables.value(of: name)
    }

    /// Writes a variable by index from inside the graph. A non-negative `bit`
    /// sets or clears that bit of the stored word.
    public func writeVariable(_ value: BehaviorVariableValue, at index: Int, bit: Int = -1) {
        guard let current = variables.value(at: index) else { return }
        variablesWrittenThisUpdate.insert(index)
        guard bit >= 0 else {
            variables.setValue(value, at: index)
            return
        }
        guard bit < 32 else { return }
        let mask = 1 << bit
        let word = value.boolValue ? current.intValue | mask : current.intValue & ~mask
        variables.setValue(.int(Int32(truncatingIfNeeded: word)), at: index)
    }

    /// Raises an event by name, visible to the *next* update.
    @discardableResult
    public func raiseEvent(named name: String, payload: String? = nil) -> Bool {
        events.raise(named: name, payload: payload)
    }
}
