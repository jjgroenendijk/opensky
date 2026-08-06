// The AS2 bytecode interpreter (milestone 8.3.2): the execution loop, the
// dispatch fan-out, and the bounds every invocation runs under — an action
// budget, a call-depth cap, and a re-entry cap.
//
// The loop walks `SWFActionBlock.records` by index rather than by byte offset,
// because the parser already framed the stream; a branch converts its byte
// target back to an index through `SWFActionBlock.index(atOffset:)`, and a
// target that starts no record is a recorded fault instead of a crash. Function
// bodies execute as an index range inside the same block, so a `return` and a
// branch behave identically at any nesting depth.
//
// Calls run on the interpreter's own frame stack (`frames`), not on the Swift
// stack: calling a bytecode function pushes a frame carrying its own
// instruction pointer, and the popped frame's value lands wherever its
// `AS2FrameCompletion` says. That is what makes `AS2Limits.callDepth` a policy
// limit instead of a stack-safety limit (issue #132) — CLIK component
// constructors chain deeper than the old Swift-recursive limit of 64 allowed,
// and every one that was cut short skipped `EventDispatcher.initialize`.
// Swift recursion remains only where a value is needed synchronously inside a
// Swift call — a built-in like `Function.prototype.apply`, or a property
// accessor — and `AS2Limits.reentryDepth` bounds that path.
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
    /// A call pushed a frame; the loop runs it and resumes this one after.
    case called
}

/// What starting a call produced.
nonisolated enum AS2CallStart {
    /// A built-in ran to completion here and now.
    case value(AS2Value)
    /// A bytecode frame was pushed onto the interpreter's call stack.
    case pushed
}

nonisolated final class AS2Interpreter {
    let runtime: AS2Runtime

    private var remainingBudget: Int
    /// The explicit call stack, innermost last. Internal rather than private
    /// because `AS2InterpreterCallPath` pushes onto it.
    var frames: [AS2Frame] = []
    /// Live frames and built-ins that a call pushed, which is what
    /// `AS2Limits.callDepth` bounds. The frame an entry point starts with does
    /// not count.
    var callDepth = 0
    /// Nested interpreter loops running underneath a Swift call.
    var reentryDepth = 0
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
        frame.range = block.records.indices
        frame.index = block.records.startIndex
        return finish { () throws(AS2Fault) -> AS2Value in
            try self.runBase(frame)
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
            let base = self.frames.count
            let start = try self.startCall(
                function,
                AS2CallSite(thisValue: thisValue, arguments: arguments, offset: 0)
            )
            switch start {
            case let .value(value):
                return value
            case .pushed:
                return try self.runFrames(baseDepth: base)
            }
        }
    }

    /// Pushes `frame` as the base of an interpreter loop and runs it out.
    private func runBase(_ frame: AS2Frame) throws(AS2Fault) -> AS2Value {
        let base = frames.count
        frame.completion = .value
        frames.append(frame)
        return try runFrames(baseDepth: base)
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

    /// Runs frames until the stack drops back to `baseDepth`, and returns the
    /// value the frame that started there produced. A call inside it pushes
    /// another frame instead of recursing, so the depth this loop reaches is
    /// bounded by memory rather than by the Swift stack.
    func runFrames(baseDepth: Int) throws(AS2Fault) -> AS2Value {
        defer { unwind(to: baseDepth) }
        var result = AS2Value.undefined
        while frames.count > baseDepth {
            guard let frame = frames.last else {
                break
            }
            guard frame.index < frame.range.upperBound else {
                result = try complete(returning: .undefined)
                continue
            }
            let record = frame.block.records[frame.index]
            frame.currentOffset = record.offset
            try consumeBudget(offset: record.offset)
            frame.index += 1
            switch try step(record, frame: frame) {
            case .next, .called:
                continue
            case let .jump(destination):
                frame.index = destination
            case let .done(value):
                result = try complete(returning: value)
            }
        }
        return result
    }

    /// Pops the finished frame and hands its value to whoever asked for it: the
    /// caller's operand stack, or the entry point that started the loop.
    private func complete(returning value: AS2Value) throws(AS2Fault) -> AS2Value {
        let finished = frames.removeLast()
        if finished.isCall {
            callDepth -= 1
        }
        guard let caller = frames.last else {
            return value
        }
        switch finished.completion {
        case .value:
            break
        case .push:
            try caller.push(value)
        case let .construct(instance):
            try caller.push(value.objectValue.map(AS2Value.object) ?? .object(instance))
        }
        return value
    }

    /// Drops the frames a fault abandoned, so an interpreter that a built-in
    /// keeps using after catching one is not left with a stale stack.
    private func unwind(to depth: Int) {
        while frames.count > depth {
            if frames.removeLast().isCall {
                callDepth -= 1
            }
        }
    }

    private func step(
        _ record: SWFActionRecord,
        frame: AS2Frame
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
        if let flow = try callOp(record, frame: frame) {
            return flow
        }
        if let flow = try controlOp(record, frame: frame) {
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
        frame: AS2Frame
    ) throws(AS2Fault) -> Int {
        let range = frame.range
        if let index = frame.block.index(atOffset: byteOffset), range.contains(index) {
            return index
        }
        if let last = range.last, frame.block.records[last].endOffset == byteOffset {
            return range.upperBound
        }
        throw AS2Fault.invalidJump(offset: frame.currentOffset, target: byteOffset)
    }

    /// Runs a built-in, mapping its untyped `throws` back onto `AS2Fault`.
    func invokeNative(
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
}
