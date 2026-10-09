// The shell of the idle runtime: sends sandboxing actors to free idle markers,
// runs the selector on arrival, plays the clip, and shows the prop. The rules
// live in `IdleCore` and `IdleSelector`. See docs/engine/idle-runtime.md.

import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// What the idle coordinator reads from the session.
@MainActor
public protocol IdleWorld: AnyObject {
    /// Every resident REFR, or nil when no cell is streamed.
    func idleReferencePlacements() -> [IdleReferencePlacement]?
    func idleActors() -> [IdleActorPresence]
    /// The live state one condition list reads; the coordinator sets the subject.
    func idleConditionContext() -> ConditionContext
    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback?
    /// The clock actor clips play on; nil without a renderer.
    var idleAnimationTime: Float? { get }
    func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult
    /// Shows a prop on the actor, or removes it with nil. It rebuilds no cell.
    func setProp(_ prop: ActorPropAttachment?, on actor: ReferenceKey)
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
        let end: Float
        let hasProp: Bool
        /// The playback the clip went to; a cell rebuild replaces it. Nil for the player,
        /// who has none, so only the events play.
        var playback: ObjectIdentifier?
        /// Annotations still to send, as absolute animation times.
        var events: [IdleAnimationEvent] = []
    }

    private(set) var store: IdleStore?
    private var plans: IdlePlanLoader?
    var clips: ActorClipLoader?
    var sessions: [ReferenceKey: Session] = [:]
    var reports: [ReferenceKey: IdleReport] = [:]
    /// Markers an actor could not path to, so it does not retry every frame.
    private var unreachable: [ReferenceKey: Set<ReferenceKey>] = [:]
    private(set) var markers: [IdleMarkerPlacement] = []
    private var markersRefreshAt: Float = 0
    public internal(set) var usesIdleMarkers = true
    /// Each clip annotation an idle passes, as `(actor, name)`.
    public var onAnimationEvent: ((ReferenceKey, String) -> Void)?
    /// The player has no playback, so a player idle only times its events with this rig.
    static let playerSkeletonPath = ActorAnimationClipLoader.characterRoot
        + "character assets\\skeleton.nif"
    let random: (Int) -> Int

    weak var world: (any IdleWorld)?

    public init(random: @escaping (Int) -> Int = { Int.random(in: 0 ..< max($0, 1)) }) {
        self.random = random
    }

    public func attach(world: any IdleWorld) {
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
        if now >= markersRefreshAt || now < markersRefreshAt - 10 {
            markers = resolveMarkers(world.idleReferencePlacements() ?? [])
            markersRefreshAt = now + 1
        }
        let actors = Dictionary(
            world.idleActors().map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
        )
        releaseDeparted(actors: actors, now: now)
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
            let stillPlaying = (session.playing?.end ?? 0) > now && actor != nil
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
            let due = playing.events.prefix { $0.time <= now }
            playing.events.removeFirst(due.count)
            session.playing = playing
            due.forEach { onAnimationEvent?(actor.key, $0.name) }
            if now >= playing.end {
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
        guard let chosen = selection.chosen, let plans else {
            return record(IdleReport(
                actor: actor, source: source, trace: selection.trace, chosen: nil, plan: nil,
                seconds: 0, failure: "no idle passed its conditions"
            ))
        }
        let waiting = Waiting(selection: selection, source: source, timer: timer)
        let plan: IdlePlaybackPlan
        switch plans.state(of: IdlePlanKey(chosen)) {
        case let .ready(ready): plan = ready
        case .loading: return wait(waiting, on: actor, chosen: chosen, plan: nil)
        case let .failed(failure):
            return finish(IdleReport(
                actor: actor, source: source, trace: selection.trace,
                chosen: chosen.record.editorID, plan: nil, seconds: 0, failure: failure.reason
            ), timer: timer, now: now)
        }
        let playback = world?.actorPlayback(for: actor)
        let skeleton = playback?.clip.skeletonMeshPath
            ?? (actor == .player ? Self.playerSkeletonPath : nil)
        var clipState: AssetLoadState<ActorAnimationClip>?
        if let path = plan.clipPath, let skeleton {
            clipState = clip(path, skeleton: skeleton)
        }
        if case .loading = clipState {
            return wait(waiting, on: actor, chosen: chosen, plan: plan)
        }
        var failure: String?
        var seconds: Float = 0
        if let clip = clipState?.value {
            seconds = IdleCore.playSeconds(
                clipDuration: clip.animation.duration,
                properties: chosen.record.properties,
                random: random
            )
            start(clip, plan: plan, on: actor, for: seconds, now: now)
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
        _ clip: ActorAnimationClip, plan: IdlePlaybackPlan,
        on actor: ReferenceKey, for seconds: Float, now: Float
    ) {
        let playback = world?.actorPlayback(for: actor)
        playback?.play(clip, startingAt: now, forSeconds: seconds)
        let prop = playback == nil ? nil : Self.attachment(plan.prop)
        if prop != nil || sessions[actor]?.playing?.hasProp == true {
            world?.setProp(prop, on: actor)
        }
        let events = IdleCore.playEvents(
            annotations: clip.animation.annotations, notify: plan.notify,
            clipDuration: clip.animation.duration, seconds: seconds
        ).map { IdleAnimationEvent(time: now + $0.time, name: $0.name) }
        sessions[actor, default: Session()].playing = Playing(
            clip: clip, end: now + seconds, hasProp: prop != nil,
            playback: playback.map(ObjectIdentifier.init), events: events
        )
    }

    private func finish(_ report: IdleReport, timer: Float?, now: Float) -> IdleReport {
        sessions[report.actor]?.reselectAt = IdleCore.nextSelection(
            after: now, playSeconds: report.seconds, timer: timer
        )
        return record(report)
    }
}
