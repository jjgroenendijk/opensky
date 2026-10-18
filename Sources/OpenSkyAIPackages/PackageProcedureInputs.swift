// Reads one procedure's parameters, by the `PKC2` data input indexes of its leaf,
// into the setup its machine runs. Parameter order is the Creation Kit wiki's, and
// matches the `BNAM` input names of the vanilla templates.

import OpenSkyFormatsESM
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import simd

/// The world lookups a procedure's parameters need.
@MainActor
public protocol PackageInputResolving {
    func place(of location: Package.Location) -> PackagePlace?
    func reference(of target: Package.Target) -> ReferenceKey?
    func position(of reference: ReferenceKey) -> SIMD3<Float>?
    func patrolPath(from start: Package.Target) -> [SIMD3<Float>]?
    func seat(in furniture: ReferenceKey) -> PackageSeat?
}

/// Where each kind reads its parameters, as positions in its `PKC2` list.
nonisolated struct PackageProcedureParameters: Sendable {
    var place: Int?
    var target: Int?
    var watched: Int?
    var topic: Int?
    var selector: Int?
    var seconds: Int?
    var near: Int?
    var far: Int?
    var height: Int?
    var flag: Int?
    var combat: Int?

    static let table: [PackageProcedureKind: Self] = [
        .travel: Self(place: 0), .wander: Self(place: 0), .sandbox: Self(place: 0),
        .patrol: Self(target: 0), .sleep: Self(target: 0), .sit: Self(target: 0),
        .eat: Self(selector: 0), .wait: Self(seconds: 0),
        .acquire: Self(target: 0), .activate: Self(target: 0),
        .dialogueActivate: Self(place: 1, target: 0),
        .escort: Self(place: 2, watched: 0, far: 5),
        .find: Self(place: 0, selector: 1),
        .flee: Self(place: 1, watched: 0, far: 5, flag: 2),
        .flightGrab: Self(target: 0),
        .follow: Self(watched: 0, near: 1, far: 2),
        .followTo: Self(place: 1, watched: 0, near: 2, far: 3),
        .forceGreet: Self(place: 2, topic: 0),
        .guardArea: Self(place: 0), .holdPosition: Self(place: 0),
        .hover: Self(place: 0, height: 1), .keepAnEyeOn: Self(watched: 0),
        .lockDoors: Self(place: 0), .unlockDoors: Self(place: 0),
        .orbit: Self(place: 0, near: 1, far: 2, height: 3),
        .say: Self(target: 1, topic: 0),
        .shout: Self(place: 0, target: 2, selector: 1),
        .useIdleMarker: Self(target: 0),
        .useMagic: Self(place: 0, target: 2, selector: 1),
        .useWeapon: Self(place: 0, target: 2, selector: 1, flag: 4, combat: 14)
    ]

    /// Find writes what it found into its third parameter, an object list.
    static let findOutput = 2
}

/// A leaf's machine and what the coordinator keeps beside it.
nonisolated public struct PackageLeafSetup: Equatable, Sendable {
    public var setup: PackageProcedureSetup
    public var seat: PackageSeat?
    /// A static-pathing patrol walks straight between its markers.
    public var isDirect = false
}

/// One leaf's parameter values, with the object lists earlier leaves filled.
@MainActor
public struct PackageProcedureInputs {
    public let leaf: PackageProcedureLeaf
    /// The package's data inputs by index, its own over its template's.
    public let values: [Int8: Package.DataValue]
    public let objectLists: [Int8: [ReferenceKey]]
    public let start: SIMD3<Float>
    public let seed: UInt64

    public init(
        leaf: PackageProcedureLeaf, values: [Int8: Package.DataValue],
        objectLists: [Int8: [ReferenceKey]], start: SIMD3<Float>, seed: UInt64
    ) {
        self.leaf = leaf
        self.values = values
        self.objectLists = objectLists
        self.start = start
        self.seed = seed
    }

    /// The data inputs of `package` over those of `template`, by index.
    nonisolated public static func values(
        of package: Package, template: Package?
    ) -> [Int8: Package.DataValue] {
        var values: [Int8: Package.DataValue] = [:]
        for input in (template?.dataInputs ?? []) + package.dataInputs {
            if let index = input.index {
                values[index] = input.value
            }
        }
        return values
    }

    /// The input index of the parameter at `position`, when it has one.
    public func index(at position: Int?) -> Int8? {
        guard let position, leaf.inputIndexes.indices.contains(position) else { return nil }
        return leaf.inputIndexes[position]
    }

    func value(at position: Int?) -> Package.DataValue? {
        index(at: position).flatMap { values[$0] }
    }

    func number(at position: Int?) -> Float? {
        value(at: position)?.number
    }

    /// The references a target parameter names: a filled object list, or one reference.
    func references(at position: Int?, resolver: some PackageInputResolving) -> [ReferenceKey] {
        guard let index = index(at: position) else { return [] }
        if let list = objectLists[index] {
            return list
        }
        guard case let .target(target)? = values[index] else { return [] }
        return resolver.reference(of: target).map { [$0] } ?? []
    }

    func target(at position: Int?) -> Package.Target? {
        if case let .target(target)? = value(at: position) {
            return target
        }
        return nil
    }

    func place(at position: Int?, resolver: some PackageInputResolving) -> PackagePlace? {
        guard case let .location(location)? = value(at: position) else { return nil }
        return resolver.place(of: location)
    }

    func topic(at position: Int?) -> FormID? {
        switch value(at: position) {
        case let .topic(topic)?: topic.nonNull
        default: nil
        }
    }
}
