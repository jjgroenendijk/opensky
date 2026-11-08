// The two kinds of AS2 function: a Swift built-in, and a bytecode body from
// `ActionDefineFunction` (0x9B) or `ActionDefineFunction2` (0x8E). The body is
// the next `codeSize` bytes of the defining stream, so a function keeps its
// block and start offset (SWF spec v19, pp. 92 and 111).

import Foundation

/// What a native function receives. It carries the interpreter so a built-in
/// can call back into bytecode (`Function.prototype.apply`, an array sort
/// comparator) under the same budget as its caller.
nonisolated public struct AS2CallContext {
    public let interpreter: AS2Interpreter
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
}
