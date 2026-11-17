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
}

nonisolated public enum OffscreenScheduleCore {
    /// An actor whose cell is not loaded updates every 0.3 / timescale game hours.
    static let lowUpdateHours = 0.3

    /// Game seconds between two updates of one actor: 54 at the default timescale of 20.
    public static func updateSeconds(timescale: Float = GameClock.defaultTimescale) -> Double {
        lowUpdateHours * 3600 / Double(max(timescale, 1))
    }

    /// True when an update is due: the first one, one after the interval, or after the
    /// clock went backwards.
    public static func isDue(now: Double, last: Double?, interval: Double) -> Bool {
        guard let last else { return true }
        return now < last || now - last >= interval
    }

    public enum Decision: Equatable, Sendable {
        case stays
        case place(OffscreenPlace)
        case stepOut(OffscreenPlace)
    }

    /// Where the actor goes on this update. A place in a loaded cell is reached through
    /// the door of the house the actor is in, so it walks the last part in view.
    public static func decide(
        from current: OffscreenPlace, to target: OffscreenPlace,
        targetLoaded: Bool, exit: OffscreenPlace?
    ) -> Decision {
        let near = simd_distance(current.point, target.point) <= max(target.radius, 1)
        if current.sharesCell(with: target), near {
            return .stays
        }
        if targetLoaded, case .interior = current.location, let exit {
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
    private var lastUpdate: Double?

    public func readout(for actor: ReferenceKey) -> String? {
        steps[actor]?.readout
    }

    public init(data: PackageSessionData?) {
        runtime = data.map {
            ActorPackageRuntime(store: $0.store, conditionFunctions: $0.conditionFunctions)
        }
    }

    /// One low-level update of every actor outside `residents`, when one is due.
    public func advance(
        world: any OffscreenScheduleWorld, clock: GameClock,
        residents: Set<ReferenceKey>, context: () -> ConditionContext
    ) {
        let now = clock.totalGameSeconds
        guard
            var runtime,
            OffscreenScheduleCore.isDue(
                now: now, last: lastUpdate, interval: OffscreenScheduleCore.updateSeconds()
            )
        else { return }
        lastUpdate = now
        let actors = world.offscreenActors().filter { !residents.contains($0.key) }
        reconcile(&runtime, with: actors)
        let shared = context()
        runtime.advance(clock: clock) { _ in shared }
        self.runtime = runtime
        for actor in actors where registered[actor.key] != nil {
            update(actor, package: runtime.currentPackage(for: actor.key), world: world, now: now)
        }
    }

    private func reconcile(_ runtime: inout ActorPackageRuntime, with actors: [OffscreenActor]) {
        let bases = Dictionary(actors.map { ($0.key, $0.base) }) { first, _ in first }
        let change = PackageCore.reconcile(registered: registered, residents: bases)
        for actor in change.departed {
            runtime.unregister(actor: actor)
            registered[actor] = nil
            steps[actor] = nil
        }
        for arrival in change.arrived {
            guard attempt({ try runtime.register(actor: arrival.actor, base: arrival.base) }) != nil
            else { continue }
            registered[arrival.actor] = arrival.base
        }
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
        let exit: OffscreenPlace? = if case let .interior(cell) = actor.place.location {
            world.loadedExit(from: cell)
        } else {
            nil
        }
        let step = switch OffscreenScheduleCore.decide(
            from: actor.place, to: target, targetLoaded: world.isLoaded(target), exit: exit
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

    /// The first location input of the package that names a place OpenSky can find.
    private func firstPlace(
        of package: ResolvedPackage, actor: OffscreenActor, world: any OffscreenScheduleWorld
    ) -> OffscreenPlace? {
        let values = PackageOverrideExecution(package: package).values
        for index in values.keys.sorted() {
            guard
                case let .location(location)? = values[index],
                let place = world.offscreenPlace(of: location, actor: actor)
            else { continue }
            return place
        }
        return nil
    }
}
