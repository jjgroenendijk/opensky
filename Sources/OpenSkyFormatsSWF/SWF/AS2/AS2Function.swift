// Callable objects (milestone 8.3.2): the two kinds of ActionScript 2
// function — a Swift closure supplied by the runtime's built-ins, and a
// bytecode body defined by `ActionDefineFunction` (0x9B) or
// `ActionDefineFunction2` (0x8E).
//
// A bytecode function does not own its bytes. `ActionDefineFunction` names a
// `codeSize` and the body is the next `codeSize` bytes of the same stream, so
// the closure keeps the block it was defined in plus the byte offset its body
// starts at, and reads the records back with
// `SWFActionBlock.records(from:byteCount:)`.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ActionDefineFunction" (p. 92) and "ActionDefineFunction2"
// (p. 111) for the header fields and the preload/suppress flags.

import Foundation

/// What a native function receives. It carries the interpreter so a built-in
/// can call back into bytecode (`Function.prototype.apply`, an array sort
/// comparator) under the same budget as its caller.
nonisolated public struct AS2CallContext {
    public let interpreter: AS2Interpreter
    /// The function object being called, so a constructor can reach its own
    /// `prototype`.
    public let callee: AS2Object
    public let thisValue: AS2Value
    public let arguments: [AS2Value]
    /// True when the call came from `new`, so a built-in can populate the
    /// instance it was handed instead of returning a fresh object.
    public let isConstructing: Bool

    public var runtime: AS2Runtime {
        interpreter.runtime
    }

    /// Missing arguments read as `undefined`, as ActionScript specifies.
    public func argument(_ index: Int) -> AS2Value {
        arguments.indices.contains(index) ? arguments[index] : .undefined
    }

    /// `this` as an object, or nil when the call had no object receiver.
    public var thisObject: AS2Object? {
        thisValue.objectValue
    }

    public func string(_ index: Int) throws -> String {
        try interpreter.toString(argument(index))
    }

    public func number(_ index: Int) throws -> Double {
        try interpreter.toNumber(argument(index))
    }

    public func boolean(_ index: Int) -> Bool {
        interpreter.toBoolean(argument(index))
    }
}

/// A built-in implemented in Swift. The body is allowed to throw so that a
/// built-in calling back into bytecode (`Function.prototype.apply`) propagates a
/// budget or depth abort instead of swallowing it. `AS2Interpreter` re-raises an
/// `AS2Fault` and turns anything else into `undefined`, so a native can never
/// introduce a new error type.
nonisolated public struct AS2NativeBody {
    public let name: String
    public let call: (AS2CallContext) throws -> AS2Value
}

/// A function defined by bytecode, with the scope it closed over.
nonisolated public struct AS2BytecodeBody {
    /// The parsed `ActionDefineFunction`/`ActionDefineFunction2` header.
    public let definition: SWFActionFunction
    /// The block the definition and its body live in.
    public let block: SWFActionBlock
    /// Byte offset the body starts at — the defining record's `endOffset`.
    public let bodyOffset: Int
    /// True for `ActionDefineFunction2` (0x8E), which owns a register file and
    /// preload flags. `ActionDefineFunction` (0x9B) binds parameters by name.
    public let usesRegisters: Bool
    /// The constant pool in force where the function was defined.
    public let constantPool: [String]
    /// The scope chain captured at definition time, outermost first.
    public let scope: [AS2Object]
    /// The variable target (the movie clip, once display objects exist) the
    /// definition belonged to.
    public let target: AS2Object
}

/// How an object is called.
nonisolated public enum AS2Callable {
    case native(AS2NativeBody)
    case bytecode(AS2BytecodeBody)

    public var name: String {
        switch self {
        case let .native(body): body.name
        case let .bytecode(body): body.definition.name
        }
    }
}
