// The shell of the idle runtime: sends sandboxing actors to free idle markers,
// runs the selector on arrival, plays the clip, and shows the prop. The rules
// live in `IdleCore` and `IdleSelector`. See docs/engine/idle-runtime.md.

import OpenSkyBehavior
import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyRuntimeState
import OpenSkyWorldConditions
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
    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback?
    /// The clock actor clips play on; nil without a renderer.
    var idleAnimationTime: Float? { get }
    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult
    /// Shows a prop on the actor, or removes it with nil. It rebuilds no cell.
    func setProp(_ prop: ActorPropAttachment?, on actor: ReferenceKey)
    /// Sends an idle's event to an actor that runs its own behavior graph, the player.
    /// `state` is the graph state the event enters, when the graph walk found it.
    func raiseIdleEvent(_ name: String, state: String?, on actor: ReferenceKey)
}

@MainActor
public final class IdleCoordinator {
    struct Session {
        var marker: IdleMarkerPlacement?
        var arrived = false
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
    }

    struct Playing {
        let clip: ActorAnimationClip
        let start: Float
        /// Infinite while a looping state holds until another idle replaces it.
        let end: Float
        let hasProp: Bool
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
    }

    /// One loaded clip of an idle's chain and the triggers its generator raises.
    struct Segment {
        let clip: ActorAnimationClip
        let triggers: [BehaviorClipTriggerEvent]
    }

    private(set) var store: IdleStore?
    private var plans: IdlePlanLoader?
    var clips: ActorClipLoader?
    var sessions: [ReferenceKey: Session] = [:]
    /// Where each actor's graph is after its last idle, so the next event starts there.
    var positions: [ReferenceKey: BehaviorStatePosition] = [:]
    /// Actors on a furniture marker, for the furniture condition functions.
    var furnitureUses: [ReferenceKey: FurnitureUse] = [:]
    /// When each actor that gets up from furniture stops reading `GetSitting` 4.
    var standingUntil: [ReferenceKey: Float] = [:]
    /// Actors that take each owner's idle events too, in the order they were added.
    var dependents: [ReferenceKey: [ReferenceKey]] = [:]
    var reports: [ReferenceKey: IdleReport] = [:]
    /// Markers an actor could not path to, so it does not retry every frame.
    private var unreachable: [ReferenceKey: Set<ReferenceKey>] = [:]
    private(set) var markers: [IdleMarkerPlacement] = []
    private var markersRefreshAt: Float = 0
    /// The world context one `advance` shares between its actors.
    var passContext: (sequence: UInt64, context: ConditionContext)?
    var isAdvancing = false
    public internal(set) var usesIdleMarkers = true
    /// Each clip annotation an idle passes, as `(actor, name)`.
    public var onAnimationEvent: ((ReferenceKey, String) -> Void)?
    /// The player has no playback, so a player idle only times its events with this rig.
    static let playerSkeletonPath = ActorAnimationClipLoader.characterRoot
        + "character assets\\skeleton.nif"
    let random: (Int) -> Int

    weak let world: (any IdleWorld)?

    public init(
        random: @escaping (Int) -> Int = { Int.random(in: 0 ..< max($0, 1)) },
        world: (any IdleWorld)?
    ) {
        self.random = random
        self.world = world
    }

    /// - Parameter planWorker: where plans load; nil runs them on the shared queue.
    public func wire(
        store: IdleStore,
        files: any GameFileSource,
        clips: ActorClipLoader,
        planWorker: (any AssetLoadWorking<IdlePlanKey, IdlePlaybackPlan>)? = nil
    ) {
        self.store = store
        self.clips = clips
        let load = IdlePlaybackResolver.planLoad(
            files: files, animatedObjects: store.animatedObjects
        )
        plans = IdlePlanLoader(worker: planWorker ?? SerialAssetLoadWorker(load: load))
        sessions = [:]
        reports = [:]
        markers = []
        markersRefreshAt = 0
    }

    /// Takes finished idle plans in. The frame calls it at its asset drain point.
    public func drainLoads() {
        plans?.drain()
    }

    public func advance() {
        guard let world, store != nil, let now = world.idleAnimationTime else { return }
        isAdvancing = true
        defer {
            isAdvancing = false
            passContext = nil
        }
        if now >= markersRefreshAt || now < markersRefreshAt - 10 {
            markers = resolveMarkers(world.idleReferencePlacements() ?? [])
            markersRefreshAt = now + 1
        }
        let actors = Dictionary(
            world.idleActors().map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
        )
        releaseDeparted(actors: actors, now: now)
        advanceSitStates(now: now)
        claimMarkers(actors: actors)
        for key in sessions.keys.sorted() {
            guard let actor = actors[key] else { continue }
            step(actor, now: now)
        }
    }

    // MARK: - Markers

    private func resolveMarkers(_ placements: [IdleReferencePlacement]) -> [IdleMarkerPlacement] {
        guard let store else { return [] }
        return placements.compactMap { placement in
            store.markers.resolve(placement.base, fromPlugin: placement.plugin).map {
                IdleMarkerPlacement(
                    reference: placement.reference,
                    marker: $0,
                    position: placement.position
                )
            }
        }
        .sorted { $0.reference < $1.reference }
    }

    /// An actor that left, died, or changed package lets go of its marker.
    private func releaseDeparted(actors: [ReferenceKey: IdleActorPresence], now: Float) {
        for (key, session) in sessions {
            let actor = actors[key]
            let keepsMarker = actor.map { !$0.isDead && IdleCore.usesMarkers($0.procedure) }
                ?? false
            let ending = session.playing.map { $0.end.isFinite && $0.end > now } ?? false
            let stillPlaying = ending && actor != nil
            guard session.marker != nil, !keepsMarker || !usesIdleMarkers else { continue }
            guard !stillPlaying else { continue }
            endIdle(of: key)
            sessions[key] = nil
        }
    }

    private func claimMarkers(actors: [ReferenceKey: IdleActorPresence]) {
        guard usesIdleMarkers, let world else { return }
        var claimed = Set(sessions.values.compactMap { $0.marker?.reference })
        for key in actors.keys.sorted() {
            guard
                let actor = actors[key], sessions[key]?.marker == nil, !actor.isDead,
                IdleCore.usesMarkers(actor.procedure),
                let marker = IdleCore.nearestFreeMarker(
                    to: actor.feet, among: markers, claimed: claimed,
                    excluded: unreachable[key] ?? []
                )
            else { continue }
            let arrived = simd_distance(actor.feet, marker.position) <= IdleCore.arrivalRadius
            if !arrived, world.moveActor(key, to: marker.position) != .started {
                unreachable[key, default: []].insert(marker.reference)
                continue
            }
            claimed.insert(marker.reference)
            var session = sessions[key] ?? Session()
            session.marker = marker
            session.arrived = arrived
            sessions[key] = session
        }
    }

    // MARK: - Playing

    private func step(_ actor: IdleActorPresence, now: Float) {
        guard var session = sessions[actor.key] else { return }
        if var playing = session.playing {
            playing.repeatLoops(until: now)
            let due = playing.events.prefix { $0.time <= now }
            playing.events.removeFirst(due.count)
            session.playing = playing
            due.forEach { onAnimationEvent?(actor.key, $0.name) }
            if now >= playing.end, !playing.followUps.isEmpty {
                session.playing = nextSegment(after: playing, on: actor.key)
            } else if now >= playing.end {
                endIdle(of: actor.key)
                session.playing = nil
            } else if
                let playback = world?.actorPlayback(for: actor.key),
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
        guard let marker = session.marker, session.arrived, now >= session.reselectAt else {
            return
        }
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
            order: IdleCore.selectionOrder(of: marker.marker.record),
            startIndex: session.nextEntry,
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
        sessions[actor]?.waiting = nil
        guard let picked = selection.chosen, let plans else {
            return record(IdleReport(
                actor: actor, source: source, trace: selection.trace, chosen: nil, plan: nil,
                seconds: 0, failure: "no idle passed its conditions"
            ))
        }
        let chosen = store?.inheritingBehaviorFile(picked) ?? picked
        let waiting = Waiting(selection: selection, source: source, timer: timer)
        let plan: IdlePlaybackPlan
        switch plans.state(of: IdlePlanKey(chosen, from: positions[actor])) {
        case let .ready(ready): plan = ready
        case .loading: return wait(waiting, on: actor, chosen: chosen, plan: nil)
        case let .failed(failure):
            return finish(IdleReport(
                actor: actor, source: source, trace: selection.trace,
                chosen: chosen.record.editorID, plan: nil, seconds: 0, failure: failure.reason
            ), timer: timer, now: now)
        }
        let skeleton = world?.actorPlayback(for: actor)?.clip.skeletonMeshPath
            ?? (actor == .player ? Self.playerSkeletonPath : nil)
        let clipStates = skeleton.map { skeleton in
            plan.clipPaths.map { clip($0, skeleton: skeleton) }
        } ?? []
        if clipStates.contains(where: Self.isLoading) {
            return wait(waiting, on: actor, chosen: chosen, plan: plan)
        }
        var failure: String?
        var seconds: Float = 0
        if let first = clipStates.first??.value {
            let chain = Self.segments(of: plan, clips: clipStates.dropFirst().map { $0?.value })
            let holds = IdleCore.holds(plan, properties: chosen.record.properties)
            seconds = chain.isEmpty
                ? (holds ? .infinity : IdleCore.playSeconds(
                    clipDuration: first.animation.duration,
                    properties: chosen.record.properties,
                    random: random
                ))
                : first.animation.duration
            start(
                Chain(
                    first: Segment(clip: first, triggers: plan.triggers),
                    followUps: chain, holdsLast: holds
                ),
                plan: plan, on: actor, for: seconds, now: now
            )
            positions[actor] = plan.position
            if !chain.isEmpty {
                seconds = holds ? .infinity : chain
                    .reduce(seconds) { $0 + $1.clip.animation.duration }
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
    private func retry(_ waiting: Waiting, on actor: ReferenceKey, now: Float) {
        play(waiting.selection, on: actor, source: waiting.source, timer: waiting.timer, now: now)
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

    /// The player has no playback; its clip only times the events.
    private func start(
        _ chain: Chain, plan: IdlePlaybackPlan,
        on actor: ReferenceKey, for seconds: Float, now: Float
    ) {
        let segment = chain.first
        let clip = segment.clip
        leaveState(of: actor, now: now)
        let playback = world?.actorPlayback(for: actor)
        playback?.play(clip, startingAt: now, forSeconds: seconds)
        if playback == nil, let event = plan.event {
            world?.raiseIdleEvent(event, state: plan.state, on: actor)
        }
        let prop = playback == nil ? nil : Self.attachment(plan.prop)
        if prop != nil || sessions[actor]?.playing?.hasProp == true {
            world?.setProp(prop, on: actor)
        }
        let held = !seconds.isFinite
        let duration = clip.animation.duration
        let marks = Self.marks(of: segment)
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
            followUps: chain.followUps, holdsLast: chain.holdsLast
        )
    }

    /// An idle replaced before its end leaves its state, which sends the exit events.
    private func leaveState(of actor: ReferenceKey, now: Float) {
        guard let playing = sessions[actor]?.playing, now < playing.end else { return }
        playing.exitEvents.forEach { onAnimationEvent?(actor, $0) }
    }

    private func finish(_ report: IdleReport, timer: Float?, now: Float) -> IdleReport {
        sessions[report.actor]?.reselectAt = IdleCore.nextSelection(
            after: now, playSeconds: report.seconds, timer: timer
        )
        return record(report)
    }
}
