import Foundation
public import OpenSkyConditions
public import OpenSkyFormatsESM

nonisolated public struct PackageConditionResolution: ConditionResolution, Sendable {
    public static let empty = PackageConditionResolution(facts: nil)

    private let facts: [ReferenceKey: ActorPackageFacts]?

    public init(facts: [ReferenceKey: ActorPackageFacts]?) {
        self.facts = facts
    }

    /// Nil when nothing was wired; an actor with no package reads as `.some(nil)`.
    public func facts(of actor: ReferenceKey) -> ActorPackageFacts?? {
        guard let facts else { return nil }
        return .some(facts[actor])
    }
}

/// The package one actor runs now, as the package functions see it.
nonisolated public struct ActorPackageFacts: Equatable, Sendable {
    public var package: FormID
    public var procedure: PackageProcedureKind
    /// The running package's data inputs, by their `UNAM` index.
    public var dataInputs: [Int8: Package.DataValue]
    /// Data indices whose location the actor stands inside.
    public var withinLocations: Set<Int8>
    /// The `PKDT` general flags.
    public var flags: Package.GeneralFlags
    /// The `PKDT` interrupt flags.
    public var interruptFlags: UInt16

    public init(
        package: FormID,
        procedure: PackageProcedureKind,
        dataInputs: [Int8: Package.DataValue] = [:],
        withinLocations: Set<Int8> = [],
        flags: Package.GeneralFlags = [],
        interruptFlags: UInt16 = 0
    ) {
        self.package = package
        self.procedure = procedure
        self.dataInputs = dataInputs
        self.withinLocations = withinLocations
        self.flags = flags
        self.interruptFlags = interruptFlags
    }

    /// xEdit `wbPKDTInterruptFlags` bit 9, "World Interactions".
    package static let worldInteractions: UInt16 = 0x200
}
