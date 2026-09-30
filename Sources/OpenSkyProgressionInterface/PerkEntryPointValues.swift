// The values a perk entry point is evaluated over and reports. The evaluator is in
// OpenSkyProgression.

import Foundation
import OpenSkyFormatsESM

/// Which world reference each condition-tab subject is, for one evaluation.
///
/// The caller binds what it knows. A melee formula knows the perk owner and the
/// target; nothing in this engine can bind `weapon`, `item` or `enchantment`,
/// because those name inventory records rather than placed references.
nonisolated public struct PerkEvaluationSubjects: Equatable, Sendable {
    private var references: [PerkConditionSubject: ReferenceKey]

    public init(
        owner: ReferenceKey,
        target: ReferenceKey? = nil,
        attacker: ReferenceKey? = nil
    ) {
        references = [.perkOwner: owner]
        references[.target] = target
        references[.attacker] = attacker
    }

    public subscript(subject: PerkConditionSubject) -> ReferenceKey? {
        references[subject]
    }

    /// Every bound reference, which is what the condition seam is built for.
    public var boundReferences: [ReferenceKey] {
        Array(Set(references.values))
    }
}

/// One perk effect as the evaluator sees it: the function to apply, the payload
/// it reads, and the priority it declared.
nonisolated public struct PerkEntryPointOperand: Equatable, Sendable {
    public let function: PerkFunction
    /// EPFD as decoded, or nil when the effect carried none.
    public let data: PerkFunctionData?
    /// PRKE byte 2, verbatim.
    public let priority: UInt8

    public init(
        function: PerkFunction,
        data: PerkFunctionData?,
        priority: UInt8 = 0
    ) {
        self.function = function
        self.data = data
        self.priority = priority
    }
}

/// Why one operand did not move the value. Every case is a counted no-op, never
/// an error and never a zero folded into the formula.
///
/// The `Error` conformance exists only so these can ride in a `Result`, which
/// is the same reason `ConditionFailure` carries one; nothing here ever throws
/// and no caller should catch one.
nonisolated public enum PerkEntryPointSkip: Equatable, Error, Sendable {
    /// A function that produces something other than a number, or the one
    /// numeric function whose randomness is undocumented. See the file header.
    case unsupportedFunction(PerkFunction)
    /// The function needs an EPFD payload and the effect carried none, or
    /// carried one of the wrong shape for its declared function.
    case missingData(PerkFunction)
    /// An actor-value function whose value the caller could not read.
    case unavailableActorValue(Int32)
    /// The arithmetic produced an infinity or a NaN, which only a mod-authored
    /// payload can do. The value is left as it arrived.
    case nonFiniteResult(PerkFunction)
}

/// What one evaluation did.
nonisolated public struct PerkEntryPointOutcome: Equatable, Sendable {
    /// The value after every applicable effect folded in.
    public let value: Float
    /// The value the caller handed in, so a readout can show both.
    public let input: Float
    /// How many operands actually moved the value.
    public let applied: Int
    /// Every operand that did not, in evaluation order.
    public let skipped: [PerkEntryPointSkip]

    /// Whether any perk changed the number.
    public var didChange: Bool {
        value != input
    }

    public init(value: Float, input: Float, applied: Int, skipped: [PerkEntryPointSkip]) {
        self.value = value
        self.input = input
        self.applied = applied
        self.skipped = skipped
    }
}
