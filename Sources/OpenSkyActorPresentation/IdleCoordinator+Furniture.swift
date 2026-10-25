// Furniture entry and exit idles, and dependent animated objects. An actor that sits plays
// the idle the `ActionActivate` tree picks for its marker and holds it. A dependent
// takes its owner's idle events, as the chopping block's executioner and guard take
// the prisoner's. See docs/engine/idle-runtime.md.

import OpenSkyConditions
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData

extension IdleCoordinator {
    /// The tree the game picks a furniture entry idle from.
    static let furnitureEntryAction = "ActionActivate"

    /// How long an actor reads `GetSitting` 4 after it gets up when no exit idle plays.
    static let standUpSeconds: Float = 1

    /// Plays the entry idle the `ActionActivate` tree picks while `actor` gets ready to
    /// sit, then marks it seated. An NPC whose sit idle still loads reads `GetSitting` 1
    /// until it plays; the player and a bed or lean never do (CK wiki "GetSitting").
    @discardableResult
    public func enterFurniture(_ actor: ReferenceKey, use: FurnitureUse) -> IdleReport? {
        guard let store, let now = world?.idleAnimationTime else { return nil }
        standingUntil[actor] = nil
        var entering = use
        entering.sitState = .readyToSit
        furnitureUses[actor] = entering
        let roots = store.roots(underAction: Self.furnitureEntryAction)
        let selection = selector(for: actor).select(roots: roots)
        let report = play(selection, on: actor, source: "furniture", now: now)
        let loads = report.failure == "loading" && actor != .player
            && use.animationType == Self.sitAnimationType
        entering.sitState = loads ? .loading : .sitting
        furnitureUses[actor] = entering
        return report
    }

    /// Plays the exit idle the `ActionActivate` tree picks once the actor reads
    /// `GetSitting` 4. The actor reads 4 until the exit clip ends, or for
    /// `standUpSeconds` when no exit idle plays; then the seat idle just stops.
    /// Without `playsExit`, as after a teleport, the seat idle just stops.
    @discardableResult
    public func leaveFurniture(_ actor: ReferenceKey, playsExit: Bool = true) -> IdleReport? {
        guard furnitureUses[actor] != nil else { return nil }
        let now = world?.idleAnimationTime ?? 0
        furnitureUses[actor]?.sitState = .readyToStand
        let report = store.flatMap { store -> IdleReport? in
            guard playsExit else { return nil }
            let roots = store.roots(underAction: Self.furnitureEntryAction)
            return play(
                selector(for: actor).select(roots: roots),
                on: actor,
                source: Self.furnitureExitSource,
                now: now
            )
        }
        // A loading exit plays when it arrives; the seat idle holds until then.
        if report?.failure == "loading" {
            standingUntil[actor] = now ... now + Self.exitLoadSeconds
            return report
        }
        let exitSeconds = report.flatMap(Self.exitSeconds)
        if exitSeconds == nil {
            stopSeatIdle(of: actor)
        }
        standingUntil[actor] = now ... now + (exitSeconds ?? Self.standUpSeconds)
        return report
    }

    /// How long a loading exit idle may take before the actor just stands.
    static let exitLoadSeconds: Float = 3
    static let furnitureExitSource = "furniture exit"

    /// Whether the actor's exit idle is still loading, so it has not left the seat yet.
    public func isExitLoading(_ actor: ReferenceKey) -> Bool {
        furnitureUses[actor]?.sitState == .readyToStand
            && sessions[actor]?.waiting?.source == Self.furnitureExitSource
    }

    /// An exit idle that waited for its load times the stand-up once it plays.
    func exitArrived(_ report: IdleReport, now: Float) {
        guard
            report.source == Self.furnitureExitSource,
            furnitureUses[report.actor]?.sitState == .readyToStand
        else { return }
        guard let seconds = Self.exitSeconds(report) else {
            stopSeatIdle(of: report.actor)
            return
        }
        standingUntil[report.actor] = now ... now + seconds
    }

    private static func exitSeconds(_ report: IdleReport) -> Float? {
        report.failure == nil && report.seconds.isFinite && report.seconds > 0 ? report
            .seconds : nil
    }

    private func stopSeatIdle(of actor: ReferenceKey) {
        endIdle(of: actor)
        sessions[actor]?.playing = nil
        sessions[actor]?.waiting = nil
    }

    /// How the clip `actor` plays now moves its root, and the seconds into the clip.
    public func rootMotion(of actor: ReferenceKey)
        -> (motion: AnimationRootMotion, elapsed: Float)?
    {
        guard
            let playing = sessions[actor]?.playing,
            let motion = playing.rootMotion,
            let now = world?.idleAnimationTime
        else { return nil }
        return (motion, now - playing.start)
    }

    /// The actor's last idle play: what it chose and why nothing played, if nothing did.
    public func lastReport(of actor: ReferenceKey) -> IdleReport? {
        reports[actor]
    }

    /// Who sits where, for every condition context: `GetSitting` in a quest, a topic, or
    /// `Actor.GetSitState`, not only in the idle trees.
    public var furnitureResolution: FurnitureConditionResolution {
        FurnitureConditionResolution(uses: furnitureUses, isAvailable: true)
    }

    /// xEdit's furniture animation enum: 1 sit.
    static let sitAnimationType: UInt32 = 1

    /// A loading sit becomes seated once its idle plays; a stand-up ends on time.
    func advanceSitStates(now: Float) {
        for (actor, use) in furnitureUses where use.sitState == .loading {
            if sessions[actor]?.playing != nil {
                furnitureUses[actor]?.sitState = .sitting
            }
        }
        // A clock that went back, such as after a load, also ends the stand-up.
        for (actor, span) in standingUntil where now >= span.upperBound || now < span.lowerBound {
            standingUntil[actor] = nil
            if isExitLoading(actor) {
                stopSeatIdle(of: actor)
            }
            if furnitureUses[actor]?.sitState == .readyToStand {
                furnitureUses[actor] = nil
            }
        }
    }

    public func addDependent(_ dependent: ReferenceKey, of owner: ReferenceKey) {
        guard dependent != owner, dependents[owner]?.contains(dependent) != true else { return }
        dependents[owner, default: []].append(dependent)
    }

    public func removeDependent(_ dependent: ReferenceKey, of owner: ReferenceKey) {
        dependents[owner]?.removeAll { $0 == dependent }
        if dependents[owner]?.isEmpty == true {
            dependents[owner] = nil
        }
    }

    /// The owner and every dependent below it, each once, owner first.
    func withDependents(_ owner: ReferenceKey) -> [ReferenceKey] {
        var order: [ReferenceKey] = []
        var pending = [owner]
        while let next = pending.first {
            pending.removeFirst()
            guard !order.contains(next) else { continue }
            order.append(next)
            pending += dependents[next] ?? []
        }
        return order
    }
}
