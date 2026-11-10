// The AS2 runtime: one movie's global object, built-in prototypes, class
// registrations, limits, tally, and trace log. An engine holds this;
// `AS2Interpreter` is created per invocation. Vanilla menus are mostly class
// registration, so `_global` and `Object.registerClass` are readable here.

import Foundation

nonisolated public final class AS2Runtime {
    public let limits: AS2Limits
    public let coercion: AS2Coercion
    public let host: any AS2Host

    /// `_global`, and the last stop of every unqualified name lookup.
    public let globalObject = AS2Object()
    /// Globals a movie tests before it sets them, so a miss on them is no demand on the engine.
    public var unsetGlobals: Set<String> = []
    /// The variable target a stream runs against when the caller names none.
    /// A later milestone replaces this with the movie's root display object.
    public let root = AS2Object()

    public let objectPrototype: AS2Object
    public let functionPrototype: AS2Object
    public let arrayPrototype: AS2Object
    public let stringPrototype: AS2Object
    public let numberPrototype: AS2Object
    public let booleanPrototype: AS2Object

    public private(set) var tally: AS2Tally
    public private(set) var traceLog: AS2TraceLog
    /// Symbol name to constructor, as `Object.registerClass` recorded it.
    public private(set) var registeredClasses: [String: AS2Object] = [:]
    private var randomState: UInt64

    /// Registrations kept. A movie that registers more than this is either
    /// generated or malformed; the excess is tallied instead of stored.
    static let registeredClassLimit = 4096

    public init(
        swfVersion: UInt8 = 9,
        host: any AS2Host = AS2RecordingHost(),
        limits: AS2Limits = .standard,
        randomSeed: UInt64 = 0x2545_F491_4F6C_DD1D
    ) {
        self.limits = limits
        self.host = host
        coercion = AS2Coercion(swfVersion: swfVersion)
        tally = AS2Tally(limits: limits)
        traceLog = AS2TraceLog(limits: limits)
        randomState = randomSeed == 0 ? 1 : randomSeed
        let base = AS2Object()
        objectPrototype = base
        functionPrototype = AS2Object(prototype: base)
        arrayPrototype = AS2Object(prototype: base)
        stringPrototype = AS2Object(prototype: base)
        numberPrototype = AS2Object(prototype: base)
        booleanPrototype = AS2Object(prototype: base)
        globalObject.prototype = objectPrototype
        root.prototype = objectPrototype
        Self.install(into: self)
    }

    /// A `_global` member by name, for the engine-to-movie bridge.
    public func globalValue(_ name: String) -> AS2Value {
        globalObject.lookup(name)?.property.value ?? .undefined
    }

    // MARK: - Class registration

    /// `Object.registerClass(symbolName, constructor)`. Passing a non-function
    /// clears the registration, which is the documented way to unregister.
    @discardableResult
    func registerClass(symbol: String, constructor: AS2Object?) -> Bool {
        guard let constructor else {
            registeredClasses[symbol] = nil
            return true
        }
        guard
            registeredClasses[symbol] != nil
            || registeredClasses.count < AS2Runtime.registeredClassLimit
        else {
            noteMissing("Object.registerClass")
            return false
        }
        registeredClasses[symbol] = constructor
        return true
    }

    public func registeredClass(named symbol: String) -> AS2Object? {
        registeredClasses[symbol]
    }

    /// Registered symbol names, sorted so a report is stable.
    public var registeredClassNames: [String] {
        registeredClasses.keys.sorted()
    }

    // MARK: - Object factories

    public func makeObject() -> AS2Object {
        AS2Object(prototype: objectPrototype)
    }

    public func makeArray(_ elements: [AS2Value] = []) -> AS2Object {
        let array = AS2Object(prototype: arrayPrototype)
        array.markArray(length: 0)
        for (index, element) in elements.enumerated() {
            array.setElement(element, at: index)
        }
        return array
    }

    /// A function object with the `prototype` object every ActionScript
    /// function carries, so `new` and prototype assignment both work.
    public func makeFunction(_ callable: AS2Callable) -> AS2Object {
        let function = AS2Object(prototype: functionPrototype)
        function.callable = callable
        let prototype = AS2Object(prototype: objectPrototype)
        prototype.define(.object(function), for: "constructor", flags: .dontEnumerate)
        function.define(.object(prototype), for: "prototype", flags: .dontEnumerate)
        return function
    }

    public func makeNative(
        _ body: @escaping (AS2CallContext) throws -> AS2Value
    ) -> AS2Object {
        makeFunction(.native(AS2NativeBody(call: body)))
    }

    /// The built-in prototype a primitive's members come from.
    func prototype(for value: AS2Value) -> AS2Object? {
        switch value {
        case .string: stringPrototype
        case .number: numberPrototype
        case .boolean: booleanPrototype
        default: nil
        }
    }

    // MARK: - Recording

    func noteUnimplemented(opcode: UInt8) {
        tally.noteUnimplemented(opcode: opcode)
    }

    public func noteMissing(_ name: String) {
        tally.noteMissing(name)
    }

    func noteStackUnderflow() {
        tally.noteStackUnderflow()
    }

    func note(fault: AS2Fault) {
        tally.note(fault: fault)
    }

    func noteBlock(actions: Int) {
        tally.noteBlock(actions: actions)
    }

    public func noteCall() {
        tally.noteCall()
    }

    func trace(_ message: String) {
        traceLog.append(message)
    }

    /// `Math.random`, from a seeded generator so a rendered menu frame is
    /// reproducible. Uses xorshift64*, which needs no dependency and no state
    /// beyond one word.
    public func nextRandom() -> Double {
        randomState ^= randomState >> 12
        randomState ^= randomState << 25
        randomState ^= randomState >> 27
        let scrambled = randomState &* 0x2545_F491_4F6C_DD1D
        return Double(scrambled >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}

// The two kinds of AS2 function: a Swift built-in, and a bytecode body from
// `ActionDefineFunction` (0x9B) or `ActionDefineFunction2` (0x8E). The body is
// the next `codeSize` bytes of the defining stream, so a function keeps its
// block and start offset (SWF spec v19, pp. 92 and 111).

/// What a native function receives. It carries the interpreter so a built-in
/// can call back into bytecode (`Function.prototype.apply`, an array sort
/// comparator) under the same budget as its caller.
nonisolated public struct AS2CallContext {
    public let interpreter: any AS2Caller
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
    let usesRegisters: Bool
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

/// What a built-in may ask of the interpreter that called it.
nonisolated public protocol AS2Caller: AnyObject {
    var runtime: AS2Runtime { get }
    /// Calls `function` and returns its value to the built-in.
    func reenter(
        _ function: AS2Object,
        thisValue: AS2Value,
        arguments: [AS2Value],
        offset: Int
    ) throws(AS2Fault) -> AS2Value
    func getMember(_ name: String, of value: AS2Value, offset: Int) throws(AS2Fault) -> AS2Value
    func toNumber(_ value: AS2Value) throws(AS2Fault) -> Double
    func toString(_ value: AS2Value) throws(AS2Fault) -> String
    func toBoolean(_ value: AS2Value) -> Bool
}
