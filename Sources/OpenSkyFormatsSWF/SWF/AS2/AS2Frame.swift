// One execution frame: operand stack, registers, scope chain, `this`, constant
// pool, and variable target. A class so opcode handlers can take it directly.
// It only holds state and checks stack bounds. Spec: SWF v19 chapter 5.

import Foundation

/// What the interpreter does with the value a frame returns when it is popped.
nonisolated public enum AS2FrameCompletion {
    /// The frame is the base of an interpreter loop: the value is the result of
    /// the `AS2Interpreter` entry point that started it.
    case value
    /// Push the value onto the calling frame's operand stack — an ordinary call.
    case push
    /// `new`: push the object the constructor returned, or this instance when
    /// it returned no object of its own.
    case construct(AS2Object)
}

nonisolated public final class AS2Frame {
    /// Where an empty-stack read is recorded.
    public let runtime: AS2Runtime
    /// The stream this frame executes records from. Branch targets and function
    /// bodies are byte offsets into it.
    public let block: SWFActionBlock
    /// The variable target: where an assignment to an undeclared name lands.
    /// A later milestone makes this the running movie clip.
    public let target: AS2Object
    public var thisValue: AS2Value

    public var stack: [AS2Value] = []
    public var registers: [AS2Value] = []
    /// Outermost first; the last entry is where `ActionDefineLocal` writes.
    public var scope: [AS2Object] = []
    /// The pool the most recent `ActionConstantPool` installed.
    public var constantPool: [String] = []
    public var stackLimit = AS2Limits.standard.stackDepth
    /// Byte offset of the record being executed, so a fault can name it.
    public var currentOffset = 0

    /// The records this frame executes: a whole block for a timeline stream, a
    /// function body for a call.
    public var range: Range<Int> = 0 ..< 0
    /// The instruction pointer — the next record index inside `range`. It lives
    /// on the frame rather than in a local so the interpreter can suspend a
    /// frame across a call instead of recursing on the Swift stack.
    public var index = 0
    public var completion: AS2FrameCompletion = .value
    /// False for the frame an entry point starts with, true for a frame a call
    /// pushed. Only the latter count against `AS2Limits.callDepth`.
    public var isCall = false
    /// The prototype the running method was found on. `super` resolves from
    /// here, not from `thisValue.__proto__`, so a three-level hierarchy moves
    /// up one level per call. Nil outside a class method.
    public var basePrototype: AS2Object?

    /// `ActionDefineFunction` has no register header; the SWF 5 action model
    /// gives a stream four registers.
    public static let defaultRegisterCount = 4

    public init(
        runtime: AS2Runtime,
        block: SWFActionBlock,
        target: AS2Object,
        thisValue: AS2Value = .undefined
    ) {
        self.runtime = runtime
        self.block = block
        self.target = target
        self.thisValue = thisValue
    }

    /// Where `ActionDefineLocal` and `ActionDefineLocal2` write: the innermost
    /// scope, which is a function's activation object or the timeline target.
    public var localScope: AS2Object {
        scope.last ?? target
    }

    public func push(_ value: AS2Value) throws(AS2Fault) {
        guard stack.count < stackLimit else {
            throw AS2Fault.stackOverflow(offset: currentOffset)
        }
        stack.append(value)
    }

    /// Popping an empty stack yields `undefined` and is counted, not raised.
    /// Flash does the same, and vanilla bytecode depends on it: the compiler
    /// emits a join-point `ActionPop` that both branches reach with an empty
    /// stack, which occurs in 666 of the 1,180 vanilla action blocks. Treating
    /// it as a fault would abort more than half of them.
    public func pop() -> AS2Value {
        guard let value = stack.popLast() else {
            runtime.noteStackUnderflow()
            return .undefined
        }
        return value
    }

    /// The top of the stack without removing it — what `ActionStoreRegister`
    /// and `ActionPushDuplicate` read. Empty reads as `undefined`, like `pop`.
    public func peek() -> AS2Value {
        guard let value = stack.last else {
            runtime.noteStackUnderflow()
            return .undefined
        }
        return value
    }

    public func register(_ index: Int) -> AS2Value {
        registers.indices.contains(index) ? registers[index] : .undefined
    }

    /// Writes a register, ignoring an index the function never allocated —
    /// malformed bytecode must not trap.
    public func setRegister(_ index: Int, to value: AS2Value) {
        guard registers.indices.contains(index) else {
            return
        }
        registers[index] = value
    }

    /// Resolves an `ActionPush` constant-pool reference. An index past the end
    /// of the pool reads as `undefined`, which is what Flash does with a stale
    /// reference rather than failing the stream.
    public func constant(_ index: Int) -> AS2Value {
        constantPool.indices.contains(index) ? .string(constantPool[index]) : .undefined
    }
}
