// Runs the procedure of a package that a scene gives an actor: a travel package
// walks the actor to its place, and the action is done when the procedure is.
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

    public init(package: ResolvedPackage, start: SIMD3<Float>, place: PackagePlace?) {
        self.package = package.package.formID
        machine = PackageProcedureMachine(
            kind: package.procedure,
            center: place?.point ?? start,
            destination: place?.point,
            radius: Float(max(place?.radius ?? 0, 0)),
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
