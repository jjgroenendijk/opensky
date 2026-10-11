// The furniture condition functions an idle tree tests as an actor sits down:
// 159 `GetSitting`, 613 `IsFurnitureAnimType`, 614 `IsFurnitureEntryType`,
// 631 `IsEnteringInteractionQuick`, 644 `IsInFurnitureState`, and 675
// `GetGraphVariableInt`, from xEdit dev-4.1.6 wbDefinitionsTES5.pas.
// See docs/engine/condition-functions.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// How one actor uses one furniture marker.
nonisolated public struct FurnitureUse: Equatable, Sendable {
    /// `GetSitting` values, from the Creation Kit wiki page "GetSitting".
    nonisolated public enum SitState: UInt32, Sendable {
        case notSitting = 0
        case loading = 1
        case readyToSit = 2
        case sitting = 3
        case readyToStand = 4
    }

    public var sitState: SitState
    /// xEdit's furniture animation enum: 1 sit, 2 lay, 4 lean.
    public let animationType: UInt32
    /// The one entry the actor uses, in xEdit's entry enum: `0x10000` front,
    /// `0x20000` behind, `0x40000` right, `0x80000` left, `0x100000` up.
    public let entry: UInt32
    /// The furniture reference. An idle tree runs its furniture checks on it as the
    /// Target, such as `HasKeyword FurnitureExecutioner` on the chopping block.
    public let furniture: ReferenceKey?

    public init(
        sitState: SitState, animationType: UInt32, entry: UInt32, furniture: ReferenceKey?
    ) {
        self.sitState = sitState
        self.animationType = animationType
        self.entry = entry
        self.furniture = furniture
    }
}

/// Which actors use furniture now. An actor with no entry is not sitting.
nonisolated public struct FurnitureConditionResolution: ConditionResolution {
    public var uses: [ReferenceKey: FurnitureUse] = [:]
    /// False in a context with no furniture seam, so every function fails honestly.
    public var isAvailable = false

    public static let empty = FurnitureConditionResolution()

    public init(uses: [ReferenceKey: FurnitureUse] = [:], isAvailable: Bool = false) {
        self.uses = uses
        self.isAvailable = isAvailable
    }
}

/// Integer behavior-graph variables per actor. An actor listed with no value for a
/// name reads 0, as an actor whose graph does not run does.
nonisolated public struct GraphVariableResolution: ConditionResolution {
    public var values: [ReferenceKey: [String: Int]] = [:]

    public static let empty = GraphVariableResolution()

    public init(values: [ReferenceKey: [String: Int]] = [:]) {
        self.values = values
    }
}

nonisolated extension ConditionContext {
    public var furniture: FurnitureConditionResolution {
        get { self[resolution: FurnitureConditionResolution.self] }
        set { self[resolution: FurnitureConditionResolution.self] = newValue }
    }

    public var graphVariables: GraphVariableResolution {
        get { self[resolution: GraphVariableResolution.self] }
        set { self[resolution: GraphVariableResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installFurniture(_ registry: inout ConditionFunctionRegistry) {
        registerFurniture(&registry, index: 159, name: "GetSitting") { use, _ in
            Float(use?.sitState.rawValue ?? 0)
        }
        registerFurniture(&registry, index: 613, name: "IsFurnitureAnimType") { use, call in
            isTrue(use?.animationType == call.condition.parameter1.rawValue)
        }
        registerFurniture(&registry, index: 614, name: "IsFurnitureEntryType") { use, call in
            isTrue(use?.entry == call.condition.parameter1.rawValue)
        }
        // OpenSky has no quick entry, so no actor enters furniture that way.
        registerFurniture(&registry, index: 631, name: "IsEnteringInteractionQuick") { _, _ in
            0
        }
        registerFurniture(&registry, index: 644, name: "IsInFurnitureState") { use, call in
            isTrue(
                use?.sitState == .sitting
                    && use?.animationType == call.condition.parameter1.rawValue
            )
        }
        registry.register(ConditionFunction(index: 675, name: "GetGraphVariableInt") { call in
            guard let name = call.condition.parameter1Name else {
                return .failure(.unresolvedParameter(675))
            }
            return call.referenceKey().flatMap { actor in
                guard let values = call.context.graphVariables.values[actor] else {
                    return .failure(.unavailableData(.graphVariable))
                }
                return .success(Float(values[name] ?? 0))
            }
        })
    }

    private static func registerFurniture(
        _ registry: inout ConditionFunctionRegistry,
        index: UInt16,
        name: String,
        value: @escaping @Sendable (FurnitureUse?, ConditionCall) -> Float
    ) {
        let parameter: ConditionParameterType = [613, 614, 644].contains(index) ? .integer : .unused
        registry
            .register(ConditionFunction(index: index, name: name, parameter1: parameter) { call in
                let furniture = call.context.furniture
                guard furniture.isAvailable else { return .failure(.unavailableData(.furniture)) }
                let snapshot = call
                return call.referenceKey().map { value(furniture.uses[$0], snapshot) }
            })
    }
}
