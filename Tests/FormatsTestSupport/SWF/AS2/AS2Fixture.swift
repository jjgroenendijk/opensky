// Helpers for the AS2 interpreter tests (milestone 8.3.2). Action bytes come
// from `SWFActionFixture`, the byte emitter milestone 8.3.1 already added —
// there is exactly one of those in the repository and this is not a second one.
// No test reads a real `.swf` (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import OpenSkyFormats
import Testing

public enum AS2Fixture: Sendable {
    public typealias Action = SWFActionFixture.Action

    /// `ActionReturn`, appended by `evaluate` so a test can read the value the
    /// stream left on the stack.
    public static let returnAction = SWFActionFixture.noOperands(0x3E)

    public static func block(_ actions: [Action]) -> SWFActionBlock {
        SWFActionParser.parse(SWFActionFixture.stream(actions))
    }

    /// Runs the actions and returns the value `ActionReturn` popped.
    public static func evaluate(
        _ actions: [Action],
        runtime: AS2Runtime = AS2Runtime()
    ) -> AS2Value {
        result(actions, runtime: runtime).value
    }

    public static func result(
        _ actions: [Action],
        runtime: AS2Runtime = AS2Runtime()
    ) -> AS2ExecutionResult {
        runtime.execute(block(actions + [returnAction]))
    }

    /// Runs the actions with no appended `ActionReturn`, for streams that end
    /// on their own or are expected to fault.
    public static func run(
        _ actions: [Action],
        runtime: AS2Runtime = AS2Runtime()
    ) -> AS2ExecutionResult {
        runtime.execute(block(actions))
    }

    /// The number an expression produced, or NaN when it produced anything else.
    public static func number(_ value: AS2Value) -> Double {
        guard case let .number(number) = value else {
            return .nan
        }
        return number
    }

    public static func string(_ value: AS2Value) -> String? {
        guard case let .string(text) = value else {
            return nil
        }
        return text
    }

    public static func boolean(_ value: AS2Value) -> Bool? {
        guard case let .boolean(flag) = value else {
            return nil
        }
        return flag
    }

    // MARK: - Common action shapes

    public static func push(_ values: [SWFActionFixture.PushValue]) -> Action {
        SWFActionFixture.push(values)
    }

    public static func opcode(_ code: UInt8) -> Action {
        SWFActionFixture.noOperands(code)
    }

    /// `push name; push value; ActionSetVariable`.
    public static func setVariable(
        _ name: String,
        _ value: SWFActionFixture.PushValue
    ) -> [Action] {
        [push([.string(name), value]), opcode(0x1D)]
    }

    /// `push name; ActionGetVariable`.
    public static func getVariable(_ name: String) -> [Action] {
        [push([.string(name)]), opcode(0x1C)]
    }

    /// Encoded size of one record: an opcode below 0x80 is a bare byte,
    /// everything else adds a UI16 length and its payload. Branch offsets and
    /// function `codeSize` fields are computed from this rather than counted by
    /// hand.
    public static func size(_ action: Action) -> Int {
        action.code >= 0x80 ? 3 + action.operands.count : 1
    }

    public static func size(_ actions: [Action]) -> Int {
        actions.reduce(0) { $0 + size($1) }
    }

    /// `ActionJump` forward over `skipped`.
    public static func jump(over skipped: [Action]) -> Action {
        SWFActionFixture.branch(code: 0x99, offset: Int16(size(skipped)))
    }

    /// `ActionIf` back to the first record of `body`, where the branch record
    /// itself directly follows `body`.
    public static func loopBack(over body: [Action]) -> Action {
        let branch = SWFActionFixture.branch(code: 0x9D, offset: 0)
        return SWFActionFixture.branch(
            code: 0x9D, offset: Int16(-(size(body) + size(branch)))
        )
    }
}
