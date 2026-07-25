// One execution frame (milestone 8.3.2): the operand stack, register file,
// scope chain, `this`, constant pool, and variable target that an action
// stream runs against.
//
// A frame is a reference type so the opcode handlers can take it directly
// instead of threading `inout` through every one of them. It stays deliberately
// dumb — it holds state and enforces the stack bounds, and every decision about
// what a value means belongs to `AS2Interpreter`.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — the stack model in "SWF 4 Action Model" (p. 64), registers in
// "ActionStoreRegister" (p. 90), and the constant pool in
// "ActionConstantPool" (p. 91).

import Foundation

nonisolated final class AS2Frame {
    /// Where an empty-stack read is recorded.
    let runtime: AS2Runtime
    /// The stream this frame executes records from. Branch targets and function
    /// bodies are byte offsets into it.
    let block: SWFActionBlock
    /// The variable target: where an assignment to an undeclared name lands.
    /// A later milestone makes this the running movie clip.
    let target: AS2Object
    var thisValue: AS2Value

    var stack: [AS2Value] = []
    var registers: [AS2Value] = []
    /// Outermost first; the last entry is where `ActionDefineLocal` writes.
    var scope: [AS2Object] = []
    /// The pool the most recent `ActionConstantPool` installed.
    var constantPool: [String] = []
    var stackLimit = AS2Limits.standard.stackDepth
    /// Byte offset of the record being executed, so a fault can name it.
    var currentOffset = 0

    /// `ActionDefineFunction` has no register header; the SWF 5 action model
    /// gives a stream four registers.
    static let defaultRegisterCount = 4

    init(
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
    var localScope: AS2Object {
        scope.last ?? target
    }

    func push(_ value: AS2Value) throws(AS2Fault) {
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
    func pop() -> AS2Value {
        guard let value = stack.popLast() else {
            runtime.noteStackUnderflow()
            return .undefined
        }
        return value
    }

    /// The top of the stack without removing it — what `ActionStoreRegister`
    /// and `ActionPushDuplicate` read. Empty reads as `undefined`, like `pop`.
    func peek() -> AS2Value {
        guard let value = stack.last else {
            runtime.noteStackUnderflow()
            return .undefined
        }
        return value
    }

    func register(_ index: Int) -> AS2Value {
        registers.indices.contains(index) ? registers[index] : .undefined
    }

    /// Writes a register, ignoring an index the function never allocated —
    /// malformed bytecode must not trap.
    func setRegister(_ index: Int, to value: AS2Value) {
        guard registers.indices.contains(index) else {
            return
        }
        registers[index] = value
    }

    /// Resolves an `ActionPush` constant-pool reference. An index past the end
    /// of the pool reads as `undefined`, which is what Flash does with a stale
    /// reference rather than failing the stream.
    func constant(_ index: Int) -> AS2Value {
        constantPool.indices.contains(index) ? .string(constantPool[index]) : .undefined
    }
}
