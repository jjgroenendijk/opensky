// Execution limits, faults, and the result of one interpreter invocation
// (milestone 8.3.2).
//
// Bytecode arrives from a user's own game files and is never validated by
// anything upstream, so every way a stream can be wrong has to end in a
// recorded diagnostic rather than a crash or a hang (AGENTS.md
// "Reverse-engineering discipline"). A fault aborts the invocation that hit it
// and nothing else: the runtime stays usable and the tally keeps the evidence.

import Foundation

/// Why an invocation stopped early. Thrown internally, never out of a public
/// entry point — `AS2Runtime` catches it and reports it in the result and the
/// tally.
nonisolated enum AS2Fault: Error, Equatable {
    /// The operand stack grew past `AS2Limits.stackDepth`.
    case stackOverflow(offset: Int)
    /// A branch resolved to a byte offset that starts no record, or one outside
    /// the block or function body being executed.
    case invalidJump(offset: Int, target: Int)
    /// A function, `With`, or `Try` body claimed more bytes than the stream
    /// holds.
    case truncatedBody(offset: Int)
    /// The invocation used its whole action budget — a runaway loop.
    case budgetExhausted(offset: Int)
    /// Calls nested deeper than `AS2Limits.callDepth` — runaway recursion.
    case callDepthExceeded(offset: Int)
    /// Swift re-entries into the interpreter nested deeper than
    /// `AS2Limits.reentryDepth` — a built-in or a property accessor chain that
    /// keeps calling back into bytecode.
    case reentryDepthExceeded(offset: Int)

    /// Byte offset within the block where the fault was raised.
    var offset: Int {
        switch self {
        case let .stackOverflow(offset),
             let .invalidJump(offset, _), let .truncatedBody(offset),
             let .budgetExhausted(offset), let .callDepthExceeded(offset),
             let .reentryDepthExceeded(offset):
            offset
        }
    }

    /// Short stable name for the tally and the UI readout.
    var kind: String {
        switch self {
        case .stackOverflow: "stackOverflow"
        case .invalidJump: "invalidJump"
        case .truncatedBody: "truncatedBody"
        case .budgetExhausted: "budgetExhausted"
        case .callDepthExceeded: "callDepthExceeded"
        case .reentryDepthExceeded: "reentryDepthExceeded"
        }
    }
}

/// The bounds every invocation runs under. All of them are configurable so the
/// app can raise a cap for a specific movie without a rebuild, but the defaults
/// are what the engine ships with.
nonisolated struct AS2Limits: Equatable {
    /// Actions one top-level invocation may execute, shared by every nested
    /// call it makes. The largest vanilla action block is 5,886 records, so a
    /// million actions leaves roughly two orders of magnitude of headroom for
    /// loops while capping a runaway at well under a second of work.
    var actionBudget = 1_000_000
    /// Nested calls. The interpreter runs bytecode calls on its own frame stack
    /// rather than on the Swift stack, so this is a policy limit and matches
    /// Flash's own 256-frame default instead of being sized for stack safety.
    var callDepth = 256
    /// Nested re-entries into the interpreter from Swift. A built-in such as
    /// `Function.prototype.apply`, or a property accessor that has to answer
    /// with a bytecode result, needs that result synchronously and therefore
    /// runs a nested interpreter loop. Those are the only calls that consume
    /// Swift stack, so they carry their own — much smaller — cap.
    var reentryDepth = 32
    /// Operand-stack entries per frame. Flash compiles expressions, not
    /// unbounded stack machines; a few thousand entries only ever accumulate
    /// through a bug in the bytecode or in this interpreter.
    var stackDepth = 4096
    /// Registers a single `ActionDefineFunction2` may claim. The header field
    /// is a `UInt8`, and the deepest vanilla function uses 23.
    var registerCount = 256
    /// Distinct names the tally keeps per category. Totals keep counting past
    /// it, so a capped tally still reports how much it did not name.
    var tallyNames = 256
    /// Faults kept verbatim; the count keeps rising past this.
    var faultRecords = 64
    /// `ActionTrace` messages kept, oldest dropped first.
    var traceEntries = 512
    /// Characters kept per trace message.
    var traceLength = 512

    static let standard = AS2Limits()
}

/// What one invocation produced.
nonisolated struct AS2ExecutionResult: Equatable {
    /// The value the stream returned; `undefined` for a timeline block.
    let value: AS2Value
    /// Actions executed, including every nested call.
    let actionsExecuted: Int
    /// Non-nil when the invocation was aborted.
    let fault: AS2Fault?

    var completed: Bool {
        fault == nil
    }

    /// Computed rather than stored: `AS2Value.object` carries a mutable
    /// `AS2Object` reference, so the type is not `Sendable` and a stored static
    /// would be shared mutable state under Swift 6. Building the `.undefined`
    /// case per access costs nothing.
    static var empty: AS2ExecutionResult {
        AS2ExecutionResult(value: .undefined, actionsExecuted: 0, fault: nil)
    }
}
