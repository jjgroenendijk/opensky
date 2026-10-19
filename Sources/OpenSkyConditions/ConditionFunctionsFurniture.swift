// The furniture condition functions an idle tree tests as an actor sits down:
// 159 `GetSitting`, 613 `IsFurnitureAnimType`, 614 `IsFurnitureEntryType`,
// 631 `IsEnteringInteractionQuick`, 644 `IsInFurnitureState`, 162 `IsCurrentFurnitureRef`,
// 163 `IsCurrentFurnitureObj`, 637 `IsExitingInstant`, 703 `IsExitingInteractionQuick`,
// and the graph variables 675 and 447, from xEdit dev-4.1.6 wbDefinitionsTES5.pas.
// See docs/engine/condition-functions.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

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

/// One actor's running behaviour graph, read by variable name. Nil when the graph
/// declares no such variable.
nonisolated public protocol GraphVariableReading: Sendable {
    func graphVariableInt(_ name: String) -> Int?
    func graphVariableFloat(_ name: String) -> Float?
}

/// Behavior-graph variables per actor. An actor listed with no value for a name reads
/// 0, as an actor whose graph does not run does. `graphs` holds the running graphs.
nonisolated public struct GraphVariableResolution: ConditionResolution {
    public var values: [ReferenceKey: [String: Int]] = [:]
    public var floats: [ReferenceKey: [String: Float]] = [:]
    public var graphs: [ReferenceKey: any GraphVariableReading] = [:]

    public static let empty = GraphVariableResolution()

    public init(
        values: [ReferenceKey: [String: Int]] = [:],
        floats: [ReferenceKey: [String: Float]] = [:],
        graphs: [ReferenceKey: any GraphVariableReading] = [:]
    ) {
        self.values = values
        self.floats = floats
        self.graphs = graphs
    }

    /// The integer value, from a running graph before a listed table.
    public func int(_ name: String, of actor: ReferenceKey) -> Float? {
        if let graph = graphs[actor] {
            return Float(graph.graphVariableInt(name) ?? 0)
        }
        return values[actor].map { $0[name].map(Float.init) ?? 0 }
    }

    public func float(_ name: String, of actor: ReferenceKey) -> Float? {
        if let graph = graphs[actor] {
            return graph.graphVariableFloat(name) ?? 0
        }
        return floats[actor].map { $0[name] ?? 0 }
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
        // OpenSky has no quick entry or exit and no instant exit, so these read 0.
        for (index, name) in [
            (631, "IsEnteringInteractionQuick"), (637, "IsExitingInstant"),
            (703, "IsExitingInteractionQuick")
        ] {
            registerFurniture(&registry, index: UInt16(index), name: name) { _, _ in 0 }
        }
        registerFurniture(&registry, index: 644, name: "IsInFurnitureState") { use, call in
            isTrue(
                use?.sitState == .sitting
                    && use?.animationType == call.condition.parameter1.rawValue
            )
        }
        registry.register(ConditionFunction(index: 675, name: "GetGraphVariableInt") { call in
            graphVariable(call, index: 675) { graph, actor, name in
                graph.int(name, of: actor)
            }
        })
        registry.register(ConditionFunction(
            index: 447, name: "GetGraphVariableFloat"
        ) { call in
            graphVariable(call, index: 447) { graph, actor, name in
                graph.float(name, of: actor)
            }
        })
        installCurrentFurniture(&registry)
    }

    /// `CIS1` names the variable. `read` answers nil for an actor with no graph snapshot.
    private static func graphVariable(
        _ call: ConditionCall,
        index: UInt16,
        read: (GraphVariableResolution, ReferenceKey, String) -> Float?
    ) -> Result<Float, ConditionFailure> {
        guard let name = call.condition.parameter1Name else {
            return .failure(.unresolvedParameter(index))
        }
        return call.referenceKey().flatMap { actor in
            guard let value = read(call.context.graphVariables, actor, name) else {
                return .failure(.unavailableData(.graphVariable))
            }
            return .success(value)
        }
    }

    /// `ptReference` names the furniture reference; `ptFurniture` names its base form.
    private static func installCurrentFurniture(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 162, name: "IsCurrentFurnitureRef", parameter1: .formID
        ) { call in
            guard let wanted = parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(162))
            }
            return currentFurniture(call).map { isTrue($0 == wanted) }
        })
        registry.register(ConditionFunction(
            index: 163, name: "IsCurrentFurnitureObj", parameter1: .formID
        ) { call in
            guard let wanted = parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(163))
            }
            return currentFurniture(call).flatMap { furniture in
                guard let entry = furniture.flatMap({ call.context.references[$0] }) else {
                    return .success(0)
                }
                guard
                    let base = call.context.data.keywords?.resolvedID(
                        baseForm(of: entry), fromPlugin: basePlugin(of: entry.key)
                    ) else { return .failure(.unavailableData(.keyword)) }
                return .success(isTrue(ReferenceKey(resolved: base) == wanted))
            }
        })
    }

    /// The furniture reference the run-on uses, nil when it uses none.
    private static func currentFurniture(
        _ call: ConditionCall
    ) -> Result<ReferenceKey?, ConditionFailure> {
        let furniture = call.context.furniture
        guard furniture.isAvailable else { return .failure(.unavailableData(.furniture)) }
        return call.referenceKey().map { furniture.uses[$0]?.furniture }
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
