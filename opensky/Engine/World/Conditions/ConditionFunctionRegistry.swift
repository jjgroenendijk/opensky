// The CTDA condition-function table (issue #251), keyed by the raw on-disk
// function index.
//
// Skyrim defines several hundred condition functions. OpenSky implements the
// handful the engine can honestly answer today and leaves the rest to
// `ConditionTally`, which counts every miss by index so the real-data sweep can
// rank what to implement next. Registering a function OpenSky cannot really
// compute would trade a measurable gap for a silent wrong answer, so the
// registry stays small on purpose.
//
// Index numbering: the value stored in a CTDA field is the Creation Kit's
// number minus 4096, and this registry is keyed by the stored value.
//
// Shape mirrors `AS2Natives`: one `install` entry point, family installers in
// satellite files, no giant switch.

import Foundation

/// How a function reads one of its two 4-byte parameter words. The parameter is
/// stored raw by the decoder, so the function's own declaration is the only
/// thing that says what the bits mean.
nonisolated enum ConditionParameterType: Equatable, Sendable {
    /// The function ignores this parameter.
    case unused
    case formID
    case integer
    case float
}

/// One condition function: what it is called, how its parameters are typed, and
/// how to compute its value.
nonisolated struct ConditionFunction: Sendable {
    /// Raw on-disk index (Creation Kit number minus 4096).
    let index: UInt16
    /// Creation Kit name, spelled exactly as the editor spells it.
    let name: String
    let parameter1: ConditionParameterType
    let parameter2: ConditionParameterType
    /// Computes the left-hand side of the comparison, or names why it cannot.
    /// `inout` because a function may consume randomness.
    let body: @Sendable (inout ConditionCall) -> Result<Float, ConditionFailure>

    init(
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
    var creationKitIndex: Int {
        Int(index) + ConditionFunctionRegistry.creationKitOffset
    }
}

/// Lookup from raw function index to implementation.
nonisolated struct ConditionFunctionRegistry: Sendable {
    /// The Creation Kit displays every condition function index 4096 higher
    /// than the plugin stores it (UESP "CTDA Field").
    static let creationKitOffset = 4096

    /// The set the engine evaluates with. Built once; adding to it is an
    /// `install` call in `ConditionFunctions`, never a mutation from a caller.
    static let standard: ConditionFunctionRegistry = {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.install(into: &registry)
        return registry
    }()

    /// Deliberately empty, for tests that need every index to be unknown.
    static let empty = ConditionFunctionRegistry()

    private var functions: [UInt16: ConditionFunction] = [:]

    init() {}

    /// Last registration wins, so a later install can override an earlier one.
    mutating func register(_ function: ConditionFunction) {
        functions[function.index] = function
    }

    subscript(index: UInt16) -> ConditionFunction? {
        functions[index]
    }

    var count: Int {
        functions.count
    }

    var isEmpty: Bool {
        functions.isEmpty
    }

    /// Implemented indices in ascending order.
    var indices: [UInt16] {
        functions.keys.sorted()
    }

    /// Report name for an index: the Creation Kit name when the function is
    /// implemented, and the bare Creation Kit number when it is not.
    func name(for index: UInt16) -> String {
        functions[index]?.name ?? "function \(Int(index) + Self.creationKitOffset)"
    }

    /// Implemented functions in index order, for inspection surfaces.
    func sortedFunctions() -> [ConditionFunction] {
        indices.compactMap { functions[$0] }
    }
}
