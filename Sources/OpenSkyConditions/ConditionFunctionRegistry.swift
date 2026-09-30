// The CTDA condition-function table, keyed by the stored function index (the
// Creation Kit number minus 4096). Only functions OpenSky can answer honestly
// are registered; `ConditionTally` counts every miss. Family installers live in
// satellite files, like `AS2Natives`.

import Foundation

/// How a function reads one of its two 4-byte parameter words. The parameter is
/// stored raw by the decoder, so the function's own declaration is the only
/// thing that says what the bits mean.
nonisolated public enum ConditionParameterType: Equatable, Sendable {
    /// The function ignores this parameter.
    case unused
    case formID
    case integer
}

/// One condition function: what it is called, how its parameters are typed, and
/// how to compute its value.
nonisolated public struct ConditionFunction: Sendable {
    /// Raw on-disk index (Creation Kit number minus 4096).
    public let index: UInt16
    /// Creation Kit name, spelled exactly as the editor spells it.
    public let name: String
    public let parameter1: ConditionParameterType
    public let parameter2: ConditionParameterType
    /// Computes the left-hand side of the comparison, or names why it cannot.
    /// `inout` because a function may consume randomness.
    public let body: @Sendable (inout ConditionCall) -> Result<Float, ConditionFailure>

    public init(
        index: UInt16,
        name: String,
        parameter1: ConditionParameterType = .unused,
        parameter2: ConditionParameterType = .unused,
        body: @escaping @Sendable (inout ConditionCall) -> Result<Float, ConditionFailure>
    ) {
        self.index = index
        self.name = name
        self.parameter1 = parameter1
        self.parameter2 = parameter2
        self.body = body
    }

    /// Creation Kit spelling of the index, 4096 higher than the stored one.
    public var creationKitIndex: Int {
        Int(index) + ConditionFunctionRegistry.creationKitOffset
    }
}

/// Lookup from raw function index to implementation.
nonisolated public struct ConditionFunctionRegistry: Sendable {
    /// The Creation Kit displays every condition function index 4096 higher
    /// than the plugin stores it (UESP "CTDA Field").
    public static let creationKitOffset = 4096

    /// The set the engine evaluates with. Built once; adding to it is an
    /// `install` call in `ConditionFunctions`, never a mutation from a caller.
    /// Deliberately empty, for tests that need every index to be unknown.
    public static let empty = ConditionFunctionRegistry()

    private var functions: [UInt16: ConditionFunction] = [:]

    public init() {}

    /// Last registration wins, so a later install can override an earlier one.
    public mutating func register(_ function: ConditionFunction) {
        functions[function.index] = function
    }

    public subscript(index: UInt16) -> ConditionFunction? {
        functions[index]
    }

    public var count: Int {
        functions.count
    }

    public var isEmpty: Bool {
        functions.isEmpty
    }

    /// Implemented indices in ascending order.
    public var indices: [UInt16] {
        functions.keys.sorted()
    }

    /// Report name for an index: the Creation Kit name when the function is
    /// implemented, and the bare Creation Kit number when it is not.
    public func name(for index: UInt16) -> String {
        functions[index]?.name ?? "function \(Int(index) + Self.creationKitOffset)"
    }

    /// Implemented functions in index order, for inspection surfaces.
    public func sortedFunctions() -> [ConditionFunction] {
        indices.compactMap { functions[$0] }
    }
}
