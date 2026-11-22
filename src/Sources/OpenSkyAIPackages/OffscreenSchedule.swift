// Persistent actors no loaded cell holds keep their package schedules: once per low-level
// update each one takes the package its schedule names and stands at that package's place.
// See docs/engine/unloaded-actors.md.

public import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// A cell and a point in it, loaded or not.
nonisolated public struct OffscreenPlace: Equatable, Sendable {
    public let location: CellSceneLocation
    /// The worldspace editor ID of an exterior `location`; nil for an interior.
    public let worldspace: String?
    public let point: SIMD3<Float>
    /// How near the point counts as being there.
    public let radius: Float

    public init(
        location: CellSceneLocation, worldspace: String?, point: SIMD3<Float>, radius: Float = 0
    ) {
        self.location = location
        self.worldspace = worldspace
        self.point = point
        self.radius = radius
    }

    /// The same cell of the same worldspace, ignoring case.
    public func sharesCell(with other: OffscreenPlace) -> Bool {
        location == other.location && worldspace?.lowercased() == other.worldspace?.lowercased()
    }
}

/// A persistent actor with packages and the place it stands now.
nonisolated public struct OffscreenActor: Equatable, Sendable {
    public let key: ReferenceKey
    public let base: FormID
    public let place: OffscreenPlace

    public init(key: ReferenceKey, base: FormID, place: OffscreenPlace) {
        self.key = key
        self.base = base
        self.place = place
    }
}

/// What one actor's last update did, for `state packages`.
nonisolated public struct OffscreenStep: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Already at its package's place, or the package names no place OpenSky can find.
        case stays
        /// Put at its package's place.
        case placed
        /// Put outside the door of its house, in the loaded area, to walk the rest.
        case steppedOut
    }

    public let kind: Kind
    public let package: FormID?
    public let place: OffscreenPlace?
    public let gameSeconds: Double

    /// Such as `placed package 00000102 in exterior(40, -24) RiftenWorld at 10.5`.
    public var readout: String {
        let hour = gameSeconds.truncatingRemainder(dividingBy: 86400) / 3600
        let package = package.map { "package \($0) " } ?? "no package "
        let place = place.map { "in \($0.location) \($0.worldspace ?? "interior") " } ?? ""
        return "\(kind.rawValue) \(package)\(place)at \((hour * 100).rounded() / 100)"
    }
}

/// What the off-screen schedule reads from and writes to the session.
@MainActor
public protocol OffscreenScheduleWorld: AnyObject {
    /// Every living, enabled persistent actor with packages, and where it stands now.
    func offscreenActors() -> [OffscreenActor]
    /// The place a package location names for an actor that is not loaded, or nil.
    func offscreenPlace(of location: Package.Location, actor: OffscreenActor) -> OffscreenPlace?
    /// True when the cell of `place` is loaded now.
    func isLoaded(_ place: OffscreenPlace) -> Bool
    /// Where an actor leaving the interior `cell` comes out into the loaded area, or nil
    /// when no loaded door leads out of it.
    func loadedExit(from cell: FormID) -> OffscreenPlace?
    func placeOffscreenActor(_ actor: ReferenceKey, at place: OffscreenPlace)
    /// The game's `TimeScale` now.
    var offscreenTimescale: Float { get }
    /// A reading of milliseconds spent since the call, for the frame budget.
    func offscreenStopwatch() -> () -> Double
    /// The process level of an actor no loaded cell holds: Middle-low or Low.
    func offscreenLevel(of actor: OffscreenActor) -> AIProcessLevel
}

extension OffscreenScheduleWorld {
    public var offscreenTimescale: Float {
        GameClock.defaultTimescale
    }

    /// A session without a clock never runs over its budget.
    public func offscreenStopwatch() -> () -> Double {
        { 0 }
    }
}

nonisolated public enum OffscreenScheduleCore {
    /// Game seconds between two updates of one actor, the Low level's interval: 54 at
    /// the default timescale of 20.
    public static func updateSeconds(timescale: Float = GameClock.defaultTimescale) -> Double {
        AIProcessLevel.low.updateSeconds(timescale: timescale) ?? 0
    }

    /// True when an update is due: the first one, one after the interval, or after the
    /// clock went backwards.
    public static func isDue(now: Double, last: Double?, interval: Double) -> Bool {
        AIProcessRule.isDue(now: now, last: last, interval: interval)
    }

    /// The level of an unloaded actor. A worldspace's persistent cell is loaded with the
    /// worldspace, so an actor that stands in the loaded worldspace is Middle-low.
    public static func level(
        of place: OffscreenPlace, residentWorldspace: String?
    ) -> AIProcessLevel {
        var facts = AIProcessFacts()
        if let residentWorldspace, case .exterior = place.location {
            facts.cellLoaded = place.worldspace?.lowercased() == residentWorldspace.lowercased()
        }
        return AIProcessRule.level(facts) ?? .low
    }

    public enum Decision: Equatable, Sendable {
        case stays
        case place(OffscreenPlace)
        case stepOut(OffscreenPlace)
    }

    /// Where the actor goes on this update. A place in a loaded cell is reached through
    /// the door of the house the actor is in, so it walks the last part in view.
    /// `exit` is asked only then: it searches the loaded doors, and a pass runs it for
    /// hundreds of actors.
    public static func decide(
        from current: OffscreenPlace, to target: OffscreenPlace,
        targetLoaded: Bool, exit: (FormID) -> OffscreenPlace?
    ) -> Decision {
        let near = simd_distance(current.point, target.point) <= max(target.radius, 1)
        if current.sharesCell(with: target), near {
            return .stays
        }
        if targetLoaded, case let .interior(cell) = current.location, let exit = exit(cell) {
            return .stepOut(exit)
        }
        return .place(target)
    }
}

/// Runs the package selector for the persistent actors no loaded cell holds.
@MainActor
public final class OffscreenSchedule {
    var runtime: ActorPackageRuntime?
    public private(set) var registered: [ReferenceKey: FormID] = [:]
    public private(set) var steps: [ReferenceKey: OffscreenStep] = [:]
    /// The level of each listed actor at the start of the last pass.
    public private(set) var levels: [ReferenceKey: AIProcessLevel] = [:]
    private var lastUpdates: [AIProcessLevel: Double] = [:]
    /// The pass over the Low list, which goes on from its saved place next frame.
    public private(set) var turn = AIProcessTurn<ReferenceKey>()
    private var turnActors: [ReferenceKey: OffscreenActor] = [:]
    /// The budget of the last frame, in milliseconds.
    public private(set) var lastBudget: Double = 0

    public func readout(for actor: ReferenceKey) -> String? {
        steps[actor]?.readout
    }

    /// The registered actors on `level`.
    public func count(of level: AIProcessLevel) -> Int {
        registered.keys.count { (levels[$0] ?? .low) == level }
    }

    public init(data: PackageSessionData?) {
        runtime = data.map {
            ActorPackageRuntime(store: $0.store, conditionFunctions: $0.conditionFunctions)
        }
    }

    /// The Middle-low and Low levels' update. A pass starts when a level is due. Each
    /// actor of that level outside `residents` takes its package and its place in turn,
    /// inside the frame's budget. A pass that runs over goes on in the next frame.
    public func advance(
        world: any OffscreenScheduleWorld, clock: GameClock, frameSeconds: Float = 0,
        residents: Set<ReferenceKey>, context: () -> ConditionContext
    ) {
        let now = clock.totalGameSeconds
        lastBudget = AIProcessRule.budgetMilliseconds(frameSeconds: frameSeconds)
        guard runtime != nil else { return }
        if !turn.isRunning {
            beginPass(world: world, now: now, residents: residents)
        }
        guard turn.isRunning else { return }
        let shared = context()
        turn.run(budget: lastBudget, spent: world.offscreenStopwatch(), update: { key in
            guard
                let actor = turnActors[key], !residents.contains(key),
                choosePackage(for: actor, clock: clock, context: shared)
            else { return }
            update(actor, package: runtime?.currentPackage(for: key), world: world, now: now)
        })
        if !turn.isRunning {
            turnActors = [:]
        }
    }

    /// Lists the actors of each level whose update is due.
    private func beginPass(
        world: any OffscreenScheduleWorld, now: Double, residents: Set<ReferenceKey>
    ) {
        let timescale = world.offscreenTimescale
        let due = [AIProcessLevel.middleLow, .low].filter { level in
            OffscreenScheduleCore.isDue(
                now: now, last: lastUpdates[level],
                interval: level.updateSeconds(timescale: timescale) ?? 0
            )
        }
        guard !due.isEmpty else { return }
        for level in due {
            lastUpdates[level] = now
        }
        let actors = world.offscreenActors().filter { !residents.contains($0.key) }
        forgetDeparted(present: Set(actors.map(\.key)))
        levels = Dictionary(actors.map { ($0.key, world.offscreenLevel(of: $0)) }) { first, _ in
            first
        }
        let listed = actors.filter { due.contains(levels[$0.key] ?? .low) }
        turnActors = Dictionary(listed.map { ($0.key, $0) }) { first, _ in first }
        turn.begin(listed.map(\.key))
    }

    private func forgetDeparted(present: Set<ReferenceKey>) {
        for actor in registered.keys where !present.contains(actor) {
            runtime?.unregister(actor: actor)
            registered[actor] = nil
            steps[actor] = nil
        }
    }

    /// Registers the actor on its first turn and picks its package when one is due.
    /// False when the actor has no package stack.
    private func choosePackage(
        for actor: OffscreenActor, clock: GameClock, context: ConditionContext
    ) -> Bool {
        if registered[actor.key] == nil {
            guard
                attempt({ try runtime?.register(actor: actor.key, base: actor.base) }) != nil
            else { return false }
            registered[actor.key] = actor.base
        }
        runtime?.advance(actor: actor.key, clock: clock, context: context)
        return true
    }

    private func update(
        _ actor: OffscreenActor, package: ResolvedPackage?,
        world: any OffscreenScheduleWorld, now: Double
    ) {
        let formID = package?.package.formID
        guard let target = package.flatMap({ firstPlace(of: $0, actor: actor, world: world) })
        else {
            steps[actor.key] = OffscreenStep(
                kind: .stays,
                package: formID,
                place: nil,
                gameSeconds: now
            )
            return
        }
        let step = switch OffscreenScheduleCore.decide(
            from: actor.place, to: target, targetLoaded: world.isLoaded(target),
            exit: { world.loadedExit(from: $0) }
        ) {
        case .stays:
            OffscreenStep(kind: .stays, package: formID, place: target, gameSeconds: now)
        case let .place(place):
            OffscreenStep(kind: .placed, package: formID, place: place, gameSeconds: now)
        case let .stepOut(place):
            OffscreenStep(kind: .steppedOut, package: formID, place: place, gameSeconds: now)
        }
        if step.kind != .stays, let place = step.place {
            world.placeOffscreenActor(actor.key, at: place)
        }
        steps[actor.key] = step
    }

    /// The first input of the package that names a place OpenSky can find: a location, or
    /// a target that is one reference, such as the seat of a sit package.
    private func firstPlace(
        of package: ResolvedPackage, actor: OffscreenActor, world: any OffscreenScheduleWorld
    ) -> OffscreenPlace? {
        let values = PackageOverrideExecution(package: package).values
        for index in values.keys.sorted() {
            let location: Package.Location? = switch values[index] {
            case let .location(location)?: location
            case let .target(target)?: target.referenceLocation
            default: nil
            }
            if let place = location.flatMap({ world.offscreenPlace(of: $0, actor: actor) }) {
                return place
            }
        }
        return nil
    }
}
