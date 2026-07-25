// The AS2 bytecode interpreter (milestone 8.3.2): the execution loop, the
// dispatch fan-out, and the two bounds every invocation runs under — an action
// budget and a call-depth cap.
//
// The loop walks `SWFActionBlock.records` by index rather than by byte offset,
// because the parser already framed the stream; a branch converts its byte
// target back to an index through `SWFActionBlock.index(atOffset:)`, and a
// target that starts no record is a recorded fault instead of a crash. Function
// bodies execute as an index range inside the same block, so a `return` and a
// branch behave identically at any nesting depth.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionJump" and "ActionIf" (pp. 84-85) for the branch offset
// being relative to the end of the branch record.

import Foundation

/// What executing one record does to the instruction pointer.
nonisolated enum AS2Flow {
    case next
    /// Continue at this record index.
    case jump(Int)
    /// Leave the current stream with this value.
    case done(AS2Value)
}

nonisolated final class AS2Interpreter {
    let runtime: AS2Runtime

    private var remainingBudget: Int
    private var depth = 0
    private(set) var actionsExecuted = 0

    init(runtime: AS2Runtime) {
        self.runtime = runtime
        remainingBudget = runtime.limits.actionBudget
    }

    var limits: AS2Limits {
        runtime.limits
    }

    var coercion: AS2Coercion {
        runtime.coercion
    }

    // MARK: - Entry points

    /// Runs one action stream with `target` as both `this` and the variable
    /// target. Faults are recorded and reported, never thrown out.
    func execute(block: SWFActionBlock, target: AS2Object) -> AS2ExecutionResult {
        let frame = AS2Frame(
            runtime: runtime, block: block, target: target, thisValue: .object(target)
        )
        frame.stackLimit = limits.stackDepth
        frame.scope = [target]
        // The SWF 5 action model gives a timeline stream its own four registers.
        frame.registers = Array(
            repeating: .undefined, count: AS2Frame.defaultRegisterCount
        )
        return finish { () throws(AS2Fault) -> AS2Value in
            try self.run(frame: frame, range: block.records.indices)
        }
    }

    /// Calls an already-resolved function object from outside the bytecode —
    /// the engine-to-movie invoke path.
    func invoke(
        function: AS2Object,
        thisValue: AS2Value,
        arguments: [AS2Value]
    ) -> AS2ExecutionResult {
        finish { () throws(AS2Fault) -> AS2Value in
            try self.call(function, thisValue: thisValue, arguments: arguments, offset: 0)
        }
    }

    private func finish(_ body: () throws(AS2Fault) -> AS2Value) -> AS2ExecutionResult {
        do {
            let value = try body()
            runtime.noteBlock(actions: actionsExecuted)
            return AS2ExecutionResult(value: value, actionsExecuted: actionsExecuted, fault: nil)
        } catch {
            runtime.note(fault: error)
            runtime.noteBlock(actions: actionsExecuted)
            return AS2ExecutionResult(
                value: .undefined, actionsExecuted: actionsExecuted, fault: error
            )
        }
    }

    // MARK: - Loop

    /// Executes `range` of `frame.block`. Every nested body — a function, a
    /// branch target — is another range of the same records.
    func run(frame: AS2Frame, range: Range<Int>) throws(AS2Fault) -> AS2Value {
        var index = range.lowerBound
        while index < range.upperBound {
            let record = frame.block.records[index]
            frame.currentOffset = record.offset
            try consumeBudget(offset: record.offset)
            index += 1
            switch try step(record, frame: frame, range: range) {
            case .next:
                continue
            case let .jump(destination):
                index = destination
            case let .done(value):
                return value
            }
        }
        return .undefined
    }

    private func step(
        _ record: SWFActionRecord,
        frame: AS2Frame,
        range: Range<Int>
    ) throws(AS2Fault) -> AS2Flow {
        if let flow = try stackOp(record, frame: frame) {
            return flow
        }
        if let flow = try arithmeticOp(record, frame: frame) {
            return flow
        }
        if let flow = try comparisonOp(record, frame: frame) {
            return flow
        }
        if let flow = try bitwiseOp(record, frame: frame) {
            return flow
        }
        if let flow = try variableOp(record, frame: frame) {
            return flow
        }
        if let flow = try structureOp(record, frame: frame) {
            return flow
        }
        if let flow = try callOp(record, frame: frame, range: range) {
            return flow
        }
        if let flow = try controlOp(record, frame: frame, range: range) {
            return flow
        }
        if let flow = try hostOp(record, frame: frame) {
            return flow
        }
        runtime.noteUnimplemented(opcode: record.code)
        return .next
    }

    private func consumeBudget(offset: Int) throws(AS2Fault) {
        guard remainingBudget > 0 else {
            throw AS2Fault.budgetExhausted(offset: offset)
        }
        remainingBudget -= 1
        actionsExecuted += 1
    }

    // MARK: - Branch targets

    /// Converts a byte offset inside `range` to a record index. A branch that
    /// lands in the middle of a record, or outside the body being executed, is
    /// a fault — Flash's own behavior there is undefined, and a wrong index
    /// would execute arbitrary operands as opcodes.
    func recordIndex(
        forByteOffset byteOffset: Int,
        frame: AS2Frame,
        range: Range<Int>
    ) throws(AS2Fault) -> Int {
        if let index = frame.block.index(atOffset: byteOffset), range.contains(index) {
            return index
        }
        if let last = range.last, frame.block.records[last].endOffset == byteOffset {
            return range.upperBound
        }
        throw AS2Fault.invalidJump(offset: frame.currentOffset, target: byteOffset)
    }

    /// Runs a built-in, mapping its untyped `throws` back onto `AS2Fault`.
    private func invokeNative(
        _ body: AS2NativeBody,
        context: AS2CallContext
    ) throws(AS2Fault) -> AS2Value {
        do {
            return try body.call(context)
        } catch let fault as AS2Fault {
            throw fault
        } catch {
            return .undefined
        }
    }

    // MARK: - Calls

    /// Calls `function`. A non-callable object is not an error in ActionScript:
    /// the call yields `undefined`.
    func call(
        _ function: AS2Object,
        thisValue: AS2Value,
        arguments: [AS2Value],
        offset: Int,
        constructing: Bool = false
    ) throws(AS2Fault) -> AS2Value {
        guard let callable = function.callable else {
            return .undefined
        }
        runtime.noteCall()
        depth += 1
        defer { depth -= 1 }
        guard depth <= limits.callDepth else {
            throw AS2Fault.callDepthExceeded(offset: offset)
        }
        switch callable {
        case let .native(body):
            let context = AS2CallContext(
                interpreter: self,
                callee: function,
                thisValue: thisValue,
                arguments: arguments,
                isConstructing: constructing
            )
            return try invokeNative(body, context: context)
        case let .bytecode(body):
            return try callBytecode(
                body, function: function, thisValue: thisValue, arguments: arguments
            )
        }
    }
}
