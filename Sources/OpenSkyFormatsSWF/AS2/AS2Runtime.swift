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
    public static let registeredClassLimit = 4096

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
        AS2Natives.install(into: self)
    }

    // MARK: - Execution

    /// Runs one DoAction (12) or CLIPACTIONS stream.
    @discardableResult
    public func execute(_ block: SWFActionBlock, target: AS2Object? = nil) -> AS2ExecutionResult {
        AS2Interpreter(runtime: self).execute(block: block, target: target ?? root)
    }

    /// Runs one DoInitAction (59) stream — the class-registration path.
    @discardableResult
    public func execute(
        _ initAction: SWFDoInitAction,
        target: AS2Object? = nil
    ) -> AS2ExecutionResult {
        execute(initAction.actions, target: target)
    }

    /// Calls an ActionScript function from the engine. Anything that is not a
    /// function is reported as a completed no-op, so a caller invoking a menu
    /// entry point that a movie never defined does not have to special-case it.
    @discardableResult
    public func invoke(
        _ function: AS2Value,
        thisValue: AS2Value = .undefined,
        arguments: [AS2Value] = []
    ) -> AS2ExecutionResult {
        guard let callable = function.functionValue else {
            return .empty
        }
        return AS2Interpreter(runtime: self)
            .invoke(function: callable, thisValue: thisValue, arguments: arguments)
    }

    /// A `_global` member by name, for the engine-to-movie bridge.
    public func globalValue(_ name: String) -> AS2Value {
        globalObject.lookup(name)?.property.value ?? .undefined
    }

    // MARK: - Class registration

    /// `Object.registerClass(symbolName, constructor)`. Passing a non-function
    /// clears the registration, which is the documented way to unregister.
    @discardableResult
    public func registerClass(symbol: String, constructor: AS2Object?) -> Bool {
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
    public func prototype(for value: AS2Value) -> AS2Object? {
        switch value {
        case .string: stringPrototype
        case .number: numberPrototype
        case .boolean: booleanPrototype
        default: nil
        }
    }

    // MARK: - Recording

    public func noteUnimplemented(opcode: UInt8) {
        tally.noteUnimplemented(opcode: opcode)
    }

    public func noteMissing(_ name: String) {
        tally.noteMissing(name)
    }

    public func noteStackUnderflow() {
        tally.noteStackUnderflow()
    }

    public func note(fault: AS2Fault) {
        tally.note(fault: fault)
    }

    public func noteBlock(actions: Int) {
        tally.noteBlock(actions: actions)
    }

    public func noteCall() {
        tally.noteCall()
    }

    public func trace(_ message: String) {
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
