// The procedure tree of an actor's current package: one a scene or a quest alias
// gives it, or one its own schedule picked. A scene action is done when the tree is.
// See docs/engine/package-schedules.md, "Scene packages".

public import OpenSkyFormatsESM
public import OpenSkyPhysics
public import OpenSkyWorldInterface
import simd

/// The procedure tree of one actor's current package.
nonisolated public struct PackageOverrideExecution: Equatable, Sendable {
    public let package: FormID
    /// True for a package the actor's own schedule picked, false for a scene or alias one.
    public let fromSchedule: Bool
    public internal(set) var runner: PackageTreeRunner
    /// True for a package that rides the actor's horse when it has one.
    public let ridesHorse: Bool
    /// The furniture seat the actor sat down in, which it leaves with the package.
    var seat: PackageSeat?
    /// The package's preferred speed, when its flag turns it on.
    public let gait: LocomotionGait?
    /// Where the preferred speed sits between walk and run: fast walk and jog.
    public let walkRunBlend: Float?
    /// The procedure inputs by `PKC2` index, read once because every tick asks for them.
    public let values: [Int8: Package.DataValue]

    public init(package: ResolvedPackage, fromSchedule: Bool = false) {
        self.package = package.package.formID
        self.fromSchedule = fromSchedule
        ridesHorse = package.ridesHorse
        gait = Self.gait(of: package.package.general)
        walkRunBlend = Self.walkRunBlend(of: package.package.general)
        values = Self.values(of: package)
        runner = PackageTreeRunner(
            tree: package.tree, seed: UInt64(package.package.formID.rawValue)
        )
    }

    /// The procedure the readout shows.
    var machine: PackageProcedureMachine? {
        runner.primary
    }

    /// True while the walking procedure is a static-pathing patrol.
    var isDirect: Bool {
        runner.mover.flatMap { runner.running[$0]?.setup.isDirect } ?? false
    }

    /// Package ends so far: completions, and laps of a repeatable patrol.
    var ends: Int {
        runner.completions + runner.laps
    }

    /// A repeatable patrol is done after its first lap, though it keeps walking: a scene
    /// waits for the package to end, not for the actor to stop.
    public var isDone: Bool {
        runner.outcome != nil || ends > 0
    }

    static func values(of package: ResolvedPackage) -> [Int8: Package.DataValue] {
        PackageProcedureInputs.values(
            of: package.package,
            template: package.definition == package.package ? nil : package.definition
        )
    }

    /// The game's speed scale is 1.25 for fast walk and 1.5 for jog, where 1 walks and 2
    /// runs (clean-room read of `SkyrimSE.exe`, 2026-11-07).
    static func walkRunBlend(of general: Package.GeneralData) -> Float? {
        guard general.flags.contains(.usesPreferredSpeed) else { return nil }
        return switch general.preferredSpeed {
        case .fastWalk: 0.25
        case .jog: 0.5
        case .walk, .run, .unknown: nil
        }
    }

    /// Jog runs and fast walk walks, and `walkRunBlend` sets their speed.
    static func gait(of general: Package.GeneralData) -> LocomotionGait? {
        guard general.flags.contains(.usesPreferredSpeed) else { return nil }
        return switch general.preferredSpeed {
        case .walk, .fastWalk: .walk
        case .jog, .run: .run
        case .unknown: nil
        }
    }

    /// "Start At Nearest?": the walk begins at the point nearest `start`. A
    /// repeatable patrol keeps the points it skipped for its next lap; a plain one drops them.
    static func startingAtNearest(
        _ path: [SIMD3<Float>], to start: SIMD3<Float>, loops: Bool
    ) -> [SIMD3<Float>] {
        guard
            let nearest = path.indices.min(by: {
                simd_distance_squared(path[$0], start) < simd_distance_squared(path[$1], start)
            })
        else { return path }
        let tail = Array(path[nearest...])
        return loops ? tail + path[..<nearest] : tail
    }
}

/// A package location resolved to a world point.
nonisolated public struct PackagePlace: Equatable, Sendable {
    public let point: SIMD3<Float>
    public let radius: Int32

    public init(point: SIMD3<Float>, radius: Int32) {
        self.point = point
        self.radius = radius
    }
}

nonisolated extension PackageOverrideExecution {
    public var readout: PackageExecutionReadout {
        PackageExecutionReadout(
            state: machine.map { "\($0.state)" },
            pathIndex: machine?.pathIndex,
            pathCount: machine?.path.count,
            running: runner.runningMachines.map { "\($0.kind.name) \($0.state)" }
        )
    }
}
