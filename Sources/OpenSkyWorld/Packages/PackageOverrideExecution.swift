// The procedure tree of a package that a scene or a quest alias gives an actor. A
// scene action is done when the tree is.
// See docs/engine/package-schedules.md, "Scene packages".

import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldInterface
import simd

nonisolated public enum PackageOverrideProgress: Equatable, Sendable {
    case running
    /// The procedure finished, or failed because OpenSky cannot run it yet.
    case done
    /// The actor is not simulated, for example because its cell is not loaded.
    case notSimulated
}

/// The procedure tree of one overridden actor's current package.
nonisolated public struct PackageOverrideExecution: Equatable, Sendable {
    public let package: FormID
    public internal(set) var runner: PackageTreeRunner
    /// True for a package that rides the actor's horse when it has one.
    public let ridesHorse: Bool
    /// The furniture seat the actor sat down in, which it leaves with the package.
    public internal(set) var seat: PackageSeat?
    /// The package's preferred speed, when its flag turns it on.
    public let gait: LocomotionGait?

    public init(package: ResolvedPackage) {
        self.package = package.package.formID
        ridesHorse = package.ridesHorse
        gait = Self.gait(of: package.package.general)
        runner = PackageTreeRunner(
            tree: package.tree, seed: UInt64(package.package.formID.rawValue)
        )
    }

    /// The procedure the readout shows.
    public var machine: PackageProcedureMachine? {
        runner.primary
    }

    /// True while the walking procedure is a static-pathing patrol.
    public var isDirect: Bool {
        runner.mover.flatMap { runner.running[$0]?.setup.isDirect } ?? false
    }

    /// Package ends so far: completions, and laps of a repeatable patrol.
    public var ends: Int {
        runner.completions + runner.laps
    }

    /// A repeatable patrol is done after its first lap, though it keeps walking: a scene
    /// waits for the package to end, not for the actor to stop.
    public var isDone: Bool {
        runner.outcome != nil || ends > 0
    }

    /// Jog runs and fast walk walks, because an NPC has only the walk and run gaits.
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
    public static func startingAtNearest(
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

    /// The first single-reference input: the start marker a patrol names, or the
    /// furniture a sit package names.
    public static func targetInput(of package: Package) -> Package.Target? {
        for input in package.dataInputs {
            if case let .target(target) = input.value {
                return target
            }
        }
        return nil
    }
}

/// Whether a package walk started. `busy` means every mover slot is taken.
nonisolated public enum PackageMoveResult: Equatable, Sendable {
    case started
    case busy
    case failed
}

/// The furniture seat a sit package uses: the reference and its marker.
nonisolated public struct PackageSeat: Equatable, Sendable {
    public let furniture: ReferenceKey
    public let index: Int
    public let seat: FurnitureSeat

    public init(furniture: ReferenceKey, index: Int, seat: FurnitureSeat) {
        self.furniture = furniture
        self.index = index
        self.seat = seat
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
