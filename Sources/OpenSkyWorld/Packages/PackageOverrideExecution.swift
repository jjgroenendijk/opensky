// Runs the procedure of a package that a scene or a quest alias gives an actor: a
// travel package walks the actor to its place, a patrol walks its path, and a scene
// action is done when the procedure is.
// See docs/engine/package-schedules.md, "Scene packages".

import OpenSkyFormatsESM
import simd

nonisolated public enum PackageOverrideProgress: Equatable, Sendable {
    case running
    /// The procedure finished, or failed because OpenSky cannot run it yet.
    case done
    /// The actor is not simulated, for example because its cell is not loaded.
    case notSimulated
}

/// The procedure machine of one overridden actor's current package.
nonisolated public struct PackageOverrideExecution: Equatable, Sendable {
    public let package: FormID
    public private(set) var machine: PackageProcedureMachine
    /// True for a static-pathing patrol, which walks straight between its markers.
    public let isDirect: Bool
    /// True for a patrol that rides the actor's horse when it has one.
    public let ridesHorse: Bool

    /// A patrol walks `path` and needs no place.
    public init(
        package: ResolvedPackage, start: SIMD3<Float>, place: PackagePlace?,
        path: [SIMD3<Float>] = []
    ) {
        self.package = package.package.formID
        let patrol = package.procedure == .patrol ? Self.patrolFlags(package.package) : []
        isDirect = patrol.count == 4 && patrol[3]
        ridesHorse = patrol.count == 4 && patrol[2]
        machine = PackageProcedureMachine(
            kind: package.procedure,
            center: place?.point ?? start,
            destination: place?.point ?? path.first,
            radius: Float(max(place?.radius ?? 0, 0)),
            path: Array(path.dropFirst()),
            seed: UInt64(package.package.formID.rawValue)
        )
    }

    public var isDone: Bool {
        machine.state == .complete || machine.state == .failed
    }

    public mutating func start() -> [PackageProcedureCommand] {
        machine.start()
    }

    public mutating func handle(_ event: PackageProcedureEvent) -> [PackageProcedureCommand] {
        machine.handle(event)
    }

    /// The patrol procedure's Bool inputs after Patrol Start and Patrol Radius:
    /// Repeatable?, Start At Nearest?, Ride Horse if Possible?, and Static Pathing?
    /// (`PACK` `BNAM` names in the vanilla Patrol template). See
    /// docs/engine/package-schedules.md.
    public static func patrolFlags(_ package: Package) -> [Bool] {
        package.dataInputs.compactMap { input -> Bool? in
            if case let .boolean(value) = input.value {
                return value
            }
            return nil
        }
    }

    /// The first location input, which is the place a travel, sandbox, or sleep
    /// package names (UESP "Skyrim Mod:Mod File Format/PACK", `PLDT`).
    public static func location(of package: Package) -> Package.Location? {
        for input in package.dataInputs {
            if case let .location(location) = input.value {
                return location
            }
        }
        return nil
    }

    /// The first single-reference input, which is the start marker a patrol names.
    public static func patrolStart(of package: Package) -> Package.Target? {
        for input in package.dataInputs {
            if case let .target(target) = input.value {
                return target
            }
        }
        return nil
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
