// The shell of the idle runtime: sends sandboxing actors to free idle markers,
// runs the selector on arrival, plays the clip, and shows the prop. The rules
// live in `IdleCore` and `IdleSelector`. See docs/engine/idle-runtime.md.

public import OpenSkyBehavior
public import OpenSkyConditions
public import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyRuntimeState
import OpenSkyWorldConditionFunctions
public import OpenSkyWorldInterface
import simd

/// What the idle coordinator reads from the session.
@MainActor
public protocol IdleWorld: AnyObject {
    /// Every resident REFR, or nil when no cell is streamed.
    func idleReferencePlacements() -> [IdleReferencePlacement]?
    func idleActors() -> [IdleActorPresence]
    /// The live state one condition list reads; the coordinator sets the subject.
    func idleConditionContext() -> ConditionContext
    /// Advances on every state write, so a shared context is rebuilt after one.
    var idleStateSequence: UInt64 { get }
    /// The clock actor clips play on; nil without a renderer.
    var idleAnimationTime: Float? { get }
    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult
    /// Turns a standing actor towards `heading` and returns how far it still has to turn,
    /// in radians. Nil when it cannot turn at all, such as a vehicle's rider.
    func turnActor(_ actor: ReferenceKey, toHeading heading: Float, within tolerance: Float)
        -> Float?
    /// Shows a prop on the actor, or removes it with nil. It rebuilds no cell.
    func setProp(_ prop: ActorPropAttachment?, on actor: ReferenceKey)
    /// Sends an idle's event to an actor that runs its own behavior graph. `state` is the
    /// graph state the event enters, when the graph walk found it. False when no graph took it.
    func raiseIdleEvent(_ name: String, state: String?, on actor: ReferenceKey) -> Bool
    /// Each clip annotation an idle passes, in the order the clip passes them.
    func idleAnimationEvent(_ name: String, on actor: ReferenceKey)
    /// Where an actor of a pair stands now, or nil.
    func pairedActorPose(of actor: ReferenceKey) -> PairedActorPose?
    func placePairedActor(_ actor: ReferenceKey, at pose: PairedActorPose)
    /// How the synchronized clip the actor's graph runs brings it to the mark, or nil.
    func synchronizedMark(of actor: ReferenceKey) -> BehaviorSynchronizedMark?
}

/// What the idle coordinator is built from.
public struct IdleSessionData {
    public let store: IdleStore
    public let files: any GameFileSource
    public let clips: ActorClipLoader
    /// The condition functions idle conditions run on.
    public let conditionFunctions: ConditionFunctionRegistry
    /// Where plans load; nil runs them on the shared queue.
    public let planWorker: (any AssetLoadWorking<IdlePlanKey, IdlePlaybackPlan>)?

    public init(
        store: IdleStore,
        files: any GameFileSource,
        clips: ActorClipLoader,
        conditionFunctions: ConditionFunctionRegistry,
        planWorker: (any AssetLoadWorking<IdlePlanKey, IdlePlaybackPlan>)? = nil
    ) {
        self.store = store
        self.conditionFunctions = conditionFunctions
        self.files = files
        self.clips = clips
        self.planWorker = planWorker
    }
}

extension IdleSessionData {
    /// The loader of idle plans, on the session's worker or a serial one.
    func planLoader() -> IdlePlanLoader {
        let load = IdlePlaybackResolver.planLoad(files: files, animatedObjects: store.animatedObjects)
        return IdlePlanLoader(worker: planWorker ?? SerialAssetLoadWorker(load: load))
    }
}

@MainActor
public final class IdleCoordinator {
    /// Each actor's animation playback; the composition root answers it from the streamer.
    public var actorPlayback: (ReferenceKey) -> ActorAnimationPlayback? = { _ in nil }
    struct Session {
        var marker: IdleMarkerPlacement?
        var arrived = false
        var faced = false
        /// The package whose idle list this actor plays, while it has no marker.
        var packageList: FormID?
        var nextEntry = 0
        var played: Set<ResolvedFormID> = []
        var reselectAt: Float = 0
        var playing: Playing?
        /// The chosen idle while its plan or clip loads; it plays when both arrive.
        var waiting: Waiting?
    }

    struct Waiting {
        let selection: IdleSelection
        let source: String
        let timer: Float?
        var variant = 0
    }

    struct Playing {
        let clip: ActorAnimationClip
        let start: Float
        /// Infinite while a looping state holds until another idle replaces it.
        let end: Float
        var hasProp: Bool
        /// What the state sends when another idle replaces it before it ends.
        var exitEvents: [String] = []
        /// When a held idle's current loop ends and its annotations repeat.
        var loopEnd: Float?
        /// The playback the clip went to; a cell rebuild replaces it. Nil for the player,
        /// who has none, so only the events play.
        var playback: ObjectIdentifier?
        /// Annotations still to send, as absolute animation times.
        var events: [IdleAnimationEvent] = []
        /// The clip's annotations and triggers inside one loop, which a held idle repeats.
        var marks: [IdleAnimationEvent] = []
        /// Clips still to play after this one, in order.
        var followUps: [Segment] = []
        /// The last clip of the chain holds until another idle replaces it.
        var holdsLast = false
        /// The objects the clips' annotations name, and the one on the actor now.
        var animationObjects: [IdleAnimationObject] = []
        var shownObject: IdleAnimationObject?
        /// The actor's own graph plays the clips and sends their annotations.
        var throughGraph = false
        /// How the clip moves the actor's root; only a first segment carries one.
        var rootMotion: AnimationRootMotion?
    }

    /// One loaded clip of an idle's chain and the triggers its generator raises.
    struct Segment {
        let clip: ActorAnimationClip
        let triggers: [BehaviorClipTriggerEvent]
    }

    public let store: IdleStore?
    private let plans: IdlePlanLoader?
    let clips: ActorClipLoader?
    var sessions: [ReferenceKey: Session] = [:]
    /// Where each actor's graph is after its last idle, so the next event starts there.
    var positions: [ReferenceKey: BehaviorStatePosition] = [:]
    /// Actors on a furniture marker, for the furniture condition functions.
    var furnitureUses: [ReferenceKey: FurnitureUse] = [:]
    /// When each actor that gets up from furniture stops reading `GetSitting` 4.
    var standingUntil: [ReferenceKey: ClosedRange<Float>] = [:]
    /// Actors that take each owner's idle events too, in the order they were added.
    var dependents: [ReferenceKey: [ReferenceKey]] = [:]
    /// The paired animations playing now, oldest first.
    public internal(set) var pairs: [PairedAnimationPlay] = []
    var reports: [ReferenceKey: IdleReport] = [:]
    let markerClaims = IdleMarkerClaims()
    /// The world context one `advance` shares between its actors.
    var passContext: (sequence: UInt64, context: ConditionContext)?
    var isAdvancing = false
    var usesIdleMarkers = true
    /// The player has no playback, so a player idle only times its events with this rig.
    static var playerSkeletonPath: String {
        ActorClipLoader.playerSkeletonPath
    }

    /// The event that returns a graph from a held idle, as `Debug.SendAnimationEvent` sends it.
    static let defaultStateEvent = "IdleForceDefaultState"
    let random: (Int) -> Int

    weak let world: (any IdleWorld)?
    let conditionFunctions: ConditionFunctionRegistry

    public init(
        random: ((Int) -> Int)? = nil,
        world: (any IdleWorld)?,
        data: IdleSessionData?
    ) {
        let stream = RandomStream(seed: 0x4944_4C45)
        self.random = random ?? { stream.int(below: max($0, 1)) }
        self.world = world
        store = data?.store
        clips = data?.clips
        conditionFunctions = data?.conditionFunctions ?? ConditionFunctionRegistry()
        plans = data?.planLoader()
    }

    /// Takes finished idle plans in. The frame calls it at its asset drain point.
    public func drainLoads() {
        plans?.drain()
    }

    public func advance() {
        guard let world, let store, let now = world.idleAnimationTime else { return }
        isAdvancing = true
        defer {
            isAdvancing = false
            passContext = nil
        }
        markerClaims.refresh(now: now, store: store) { world.idleReferencePlacements() }
        let actors = Dictionary(
            world.idleActors().map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
        )
        releaseDeparted(actors: actors, now: now)
        advanceSitStates(now: now)
        expirePairs(now: now)
        approachMarks(now: now)
        claimMarkers(actors: actors)
        updatePackageIdles(actors: actors)
        for key in sessions.keys.sorted() {
            guard let actor = actors[key] else { continue }
            step(actor, now: now)
        }
    }

    // MARK: - Markers

    /// An actor that left, died, or changed package lets go of its marker.
    private func releaseDeparted(actors: [ReferenceKey: IdleActorPresence], now: Float) {
        for (key, session) in sessions {
            let actor = actors[key]
            let keepsMarker = actor.map { !$0.isDead && IdleCore.usesMarkers($0.procedure) }
                ?? false
            let ending = session.playing.map { $0.end.isFinite && $0.end > now } ?? false
            let stillPlaying = ending && actor != nil
            guard
                session.marker != nil, !keepsMarker || !usesIdleMarkers,
                !stillPlaying else { continue }
            endIdle(of: key)
            sessions[key] = nil
        }
    }

    private func claimMarkers(actors: [ReferenceKey: IdleActorPresence]) {
        guard usesIdleMarkers, let world else { return }
        markerClaims.claim(actors: actors, sessions: &sessions, world: world)
    }

    var markers: [IdleMarkerPlacement] {
        markerClaims.markers
    }

    // MARK: - Playing

    private func step(_ actor: IdleActorPresence, now: Float) {
        guard var session = sessions[actor.key] else { return }
        if var playing = session.playing {
            playing.repeatLoops(until: now)
            let due = playing.events.prefix { $0.time <= now }
            playing.events.removeFirst(due.count)
            due.forEach { applyAnimationObject($0.name, to: &playing, on: actor.key) }
            session.playing = playing
            if !playing.throughGraph {
                due.forEach { world?.idleAnimationEvent($0.name, on: actor.key) }
            }
            if now >= playing.end, !playing.followUps.isEmpty {
                session.playing = nextSegment(after: playing, on: actor.key)
            } else if now >= playing.end {
                endIdle(of: actor.key)
                session.playing = nil
            } else if
                !playing.throughGraph,
                let playback = actorPlayback(actor.key),
                ObjectIdentifier(playback) != playing.playback
            {
                playback.play(playing.clip, startingAt: now, forSeconds: playing.end - now)
                playing.playback = ObjectIdentifier(playback)
                session.playing = playing
            }
        }
        if
            let marker = session.marker, !session.arrived,
            simd_distance(actor.feet, marker.position) <= IdleCore.arrivalRadius
        {
            session.arrived = true
            session.reselectAt = now
        }
        sessions[actor.key] = session
        if let waiting = session.waiting {
            retry(waiting, on: actor.key, now: now)
            return
        }
        if session.marker == nil, session.packageList != nil, now >= session.reselectAt {
            selectPackageIdle(for: actor, now: now)
            return
        }
        guard
            let marker = session.marker, session.arrived, now >= session.reselectAt,
            session.faced || faces(
                marker,
                actor: actor.key
            ) else { return }
        select(at: marker, for: actor.key, now: now)
    }
}

/// Picking and playing an idle.
extension IdleCoordinator {
    /// Runs the marker's selection for `actor` and plays the winner.
    @discardableResult
    func select(at marker: IdleMarkerPlacement, for actor: ReferenceKey, now: Float) -> IdleReport {
        guard let store else {
            return failed(actor, source: marker.marker.record.editorID ?? "", "no game data")
        }
        var session = sessions[actor] ?? Session()
        let selection = selector(for: actor).select(
            entries: store.idles(of: marker.marker),
            order: (IdleCore.selectionOrder(of: marker.marker.record), session.nextEntry),
            played: IdleCore.isDoOnce(marker.marker.record) ? session.played : [],
            random: random
        )
        if let entry = selection.chosenEntry {
            session.nextEntry = entry + 1
        }
        if let chosen = selection.chosen {
            session.played.insert(chosen.id)
        }
        sessions[actor] = session
        return play(
            selection, on: actor, source: marker.marker.record.editorID ?? "marker",
            timer: marker.marker.record.idleTimer, now: now
        )
    }

    /// Plays the chosen idle, or parks it in `waiting` while its plan or clip loads.
    /// The actor keeps its current clip until then.
    @discardableResult
    func play(
        _ selection: IdleSelection,
        on actor: ReferenceKey,
        source: String,
        timer: Float? = nil,
        now: Float
    ) -> IdleReport {
        let variant = sessions[actor]?.waiting?.variant ?? planVariant(for: actor)
        sessions[actor]?.waiting = nil
        guard let picked = selection.chosen, let plans else {
            return record(IdleReport(
                actor: actor, source: source, trace: selection.trace, chosen: nil, plan: nil,
                seconds: 0, failure: "no idle passed its conditions"
            ))
        }
        let chosen = store?.inheritingBehaviorFile(picked) ?? picked
        let waiting = Waiting(selection: selection, source: source, timer: timer, variant: variant)
        let plan: IdlePlaybackPlan
        switch plans.state(of: IdlePlanKey(chosen, from: positions[actor], variant: variant)) {
        case let .ready(ready): plan = ready
        case .loading: return wait(waiting, on: actor, chosen: chosen, plan: nil)
        case let .failed(failure):
            return finish(IdleReport(
                actor: actor, source: source, trace: selection.trace,
                chosen: chosen.record.editorID, plan: nil, seconds: 0, failure: failure.reason
            ), timer: timer, now: now)
        }
        let skeleton = actorPlayback(actor)?.clip.skeletonMeshPath
            ?? (actor == .player ? Self.playerSkeletonPath : nil)
        if let skeleton, clips?.isLoading(plan, skeleton: skeleton) == true {
            return wait(waiting, on: actor, chosen: chosen, plan: plan)
        }
        var failure: String?
        var seconds: Float = 0
        let holds = IdleCore.holds(plan, properties: chosen.record.properties)
        if let skeleton, let chain = clips?.chain(of: plan, skeleton: skeleton, holds: holds) {
            seconds = chain.followUps.isEmpty
                ? (holds ? .infinity : IdleCore.playSeconds(
                    clipDuration: chain.first.duration,
                    properties: chosen.record.properties,
                    random: random
                ))
                : chain.first.duration
            start(chain, plan: plan, on: actor, at: (now, seconds))
            positions[actor] = plan.position
            if !chain.followUps.isEmpty {
                seconds = holds ? .infinity : chain.followUps.reduce(seconds) { $0 + $1.duration }
            }
        } else {
            failure = plan.clipPath == nil ? "no clip" : "the clip did not load"
        }
        return finish(IdleReport(
            actor: actor, source: source, trace: selection.trace,
            chosen: chosen.record.editorID, plan: plan, seconds: seconds, failure: failure
        ), timer: timer, now: now)
    }
}

/// Waiting for a load and recording the outcome of a play.
extension IdleCoordinator {
    /// The actor turns to the marker's facing before its first idle there.
    private func faces(_ marker: IdleMarkerPlacement, actor: ReferenceKey) -> Bool {
        let remaining = world?.turnActor(
            actor, toHeading: marker.heading, within: IdleCore.facingTolerance
        )
        if let remaining, abs(remaining) > IdleCore.facingTolerance {
            return false
        }
        sessions[actor]?.faced = true
        return true
    }

    /// An actor that runs its own graph rolls there; one without plays a rolled variant.
    private func planVariant(for actor: ReferenceKey) -> Int {
        let runsGraph = worldConditionContext().graphVariables.graphs[actor] != nil
        return runsGraph || actor == .player ? 0 : random(IdlePlanKey.variants)
    }

    private func retry(_ waiting: Waiting, on actor: ReferenceKey, now: Float) {
        let report = play(
            waiting.selection, on: actor, source: waiting.source, timer: waiting.timer, now: now
        )
        if report.failure != "loading" {
            exitArrived(report, now: now)
        }
    }

    private func wait(
        _ waiting: Waiting,
        on actor: ReferenceKey,
        chosen: ResolvedRecord<IdleAnimation>,
        plan: IdlePlaybackPlan?
    ) -> IdleReport {
        sessions[actor, default: Session()].waiting = waiting
        return record(IdleReport(
            actor: actor, source: waiting.source, trace: waiting.selection.trace,
            chosen: chosen.record.editorID, plan: plan, seconds: 0, failure: "loading"
        ))
    }

    /// The player has no playback, and a graph-driven NPC plays the idle through its
    /// graph; for both, the clip only times the idle.
    private func start(
        _ chain: Chain, plan: IdlePlaybackPlan,
        on actor: ReferenceKey, at time: (now: Float, seconds: Float)
    ) {
        let (now, seconds) = time
        let segment = chain.first
        let clip = segment.clip
        leaveState(of: actor, now: now)
        let playback = actorPlayback(actor)
        let toGraph = playback == nil || playback?.isGraphDriven == true
        let raised = toGraph && plan.event.map {
            world?.raiseIdleEvent($0, state: plan.state, on: actor) ?? false
        } ?? false
        // A graph that took the event plays the clips and sends their annotations; the
        // idle only times them, to show its animation objects.
        let graphPlays = raised && playback != nil
        if !graphPlays {
            playback?.play(clip, startingAt: now, forSeconds: seconds)
        }
        let prop = playback == nil ? nil : Playing.attachment(plan.prop)
        if prop != nil || sessions[actor]?.playing?.hasProp == true {
            world?.setProp(prop, on: actor)
        }
        let held = !seconds.isFinite
        let duration = segment.duration
        let marks = segment.marks
        let lastExit = held || !chain.followUps.isEmpty
        let events = IdleCore.playEvents(
            marks: marks,
            notify: lastExit ? BehaviorStateNotify(enter: plan.notify.enter) : plan.notify,
            clipDuration: duration, seconds: held ? duration : seconds
        ).map { IdleAnimationEvent(time: now + $0.time, name: $0.name) }
        sessions[actor, default: Session()].playing = Playing(
            clip: clip, start: now, end: now + seconds, hasProp: prop != nil,
            exitEvents: plan.notify.exit, loopEnd: held && duration > 0 ? now + duration : nil,
            playback: playback.map(ObjectIdentifier.init), events: events, marks: marks,
            followUps: chain.followUps, holdsLast: chain.holdsLast,
            animationObjects: plan.animationObjects, throughGraph: graphPlays,
            rootMotion: plan.rootMotion
        )
    }

    /// An idle replaced before its end leaves its state, which sends the exit events.
    private func leaveState(of actor: ReferenceKey, now: Float) {
        guard let playing = sessions[actor]?.playing, now < playing.end else { return }
        playing.exitEvents.forEach { world?.idleAnimationEvent($0, on: actor) }
    }

    private func finish(_ report: IdleReport, timer: Float?, now: Float) -> IdleReport {
        sessions[report.actor]?.reselectAt = IdleCore.nextSelection(
            after: now, playSeconds: report.seconds, timer: timer
        )
        return record(report)
    }
}
