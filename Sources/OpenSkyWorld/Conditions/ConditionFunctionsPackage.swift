// Package condition functions, indices from xEdit wbDefinitionsTES5.pas: 161
// GetIsCurrentPackage, 325 GetWithinPackageLocation, 611 IsNullPackageData, 612
// GetNumericPackageData, 49 GetSleeping, 255 GetOffersServicesNow, 503
// GetAllowWorldInteractions. See docs/engine/condition-functions-world.md#packages.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

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
    static let worldInteractions: UInt16 = 0x200
}

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

nonisolated extension ConditionContext {
    public var packages: PackageConditionResolution {
        get { self[resolution: PackageConditionResolution.self] }
        set { self[resolution: PackageConditionResolution.self] = newValue }
    }
}

nonisolated extension Package.DataValue {
    /// A number the package stores, or nil for a location, target, or topic.
    var number: Float? {
        switch self {
        case let .boolean(flag): flag ? 1 : 0
        case let .integer(value): Float(value)
        case let .float(value): value
        default: nil
        }
    }

    /// No form, no reference, and no place: the input was left empty.
    var isNull: Bool {
        switch self {
        case let .target(target): target.value == 0 && target.kind != .actor
        case let .location(location): location.value == 0 && location.kind != .nearSelf
            && location.kind != .nearPackageStart && location.kind != .nearEditorLocation
        case let .topic(topic): topic.rawValue == 0
        case .unknown: true
        default: false
        }
    }
}

nonisolated extension ConditionFunctions {
    public static func installPackage(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 161, name: "GetIsCurrentPackage", parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(161))
            }
            return packageFacts(call) { Self.isTrue($0?.package == parameter.asFormID) }
        })
        registry.register(ConditionFunction(
            index: 325, name: "GetWithinPackageLocation", parameter1: .integer
        ) { call in
            dataInput(call, index: 325) { facts, index in
                Self.isTrue(facts.withinLocations.contains(index))
            }
        })
        registry.register(ConditionFunction(
            index: 611, name: "IsNullPackageData", parameter1: .integer
        ) { call in
            dataInput(call, index: 611) { facts, index in
                Self.isTrue(facts.dataInputs[index]?.isNull ?? true)
            }
        })
        registry.register(ConditionFunction(
            index: 612, name: "GetNumericPackageData", parameter1: .integer
        ) { call in
            dataInput(call, index: 612) { facts, index in
                facts.dataInputs[index]?.number ?? 0
            }
        })
        installPackageFlags(&registry)
    }

    private static func installPackageFlags(_ registry: inout ConditionFunctionRegistry) {
        // 3 is "is sleeping". OpenSky has no lie-down or wake-up phase, so 1, 2, and 4
        // never occur.
        registry.register(ConditionFunction(index: 49, name: "GetSleeping") { call in
            packageFacts(call) { $0?.procedure == .sleep ? 3 : 0 }
        })
        registry.register(ConditionFunction(index: 255, name: "GetOffersServicesNow") { call in
            packageFacts(call) { Self.isTrue($0?.flags.contains(.offersServices) == true) }
        })
        registry.register(ConditionFunction(index: 503, name: "GetAllowWorldInteractions") { call in
            packageFacts(call) { facts in
                Self.isTrue((facts?.interruptFlags ?? 0) & ActorPackageFacts.worldInteractions != 0)
            }
        })
    }

    private static func packageFacts(
        _ call: ConditionCall, read: (ActorPackageFacts?) -> Float
    ) -> Result<Float, ConditionFailure> {
        call.referenceKey().flatMap { actor in
            guard let facts = call.context.packages.facts(of: actor) else {
                return .failure(.unavailableData(.package))
            }
            return .success(read(facts))
        }
    }

    /// An actor running no package has no data, so every data function reads 0.
    private static func dataInput(
        _ call: ConditionCall, index: UInt16, read: (ActorPackageFacts, Int8) -> Float
    ) -> Result<Float, ConditionFailure> {
        guard let parameter = call.parameter1 else { return .failure(.unresolvedParameter(index)) }
        let dataIndex = Int8(truncatingIfNeeded: parameter.asInt32)
        return packageFacts(call) { facts in facts.map { read($0, dataIndex) } ?? 0 }
    }
}
