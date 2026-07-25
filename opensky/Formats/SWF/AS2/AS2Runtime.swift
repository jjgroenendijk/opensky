// The AS2 runtime (milestone 8.3.2): one movie's global object, built-in
// prototypes, class registrations, execution limits, tally, and trace log.
// This is the type an engine holds; `AS2Interpreter` is created per invocation
// and is stateless between them apart from its own budget.
//
// Vanilla Skyrim menus are class-registration code — 1,127 `DoInitAction`
// blocks against 2,163 timeline `DoAction` blocks — so the interesting output
// of running one is not a rendered frame but the set of constructors it left in
// `_global` and handed to `Object.registerClass`. Both are readable here.

import Foundation

nonisolated final class AS2Runtime {
    let limits: AS2Limits
    let coercion: AS2Coercion
    let host: any AS2Host

    /// `_global`, and the last stop of every unqualified name lookup.
    let globalObject = AS2Object()
    /// The variable target a stream runs against when the caller names none.
    /// A later milestone replaces this with the movie's root display object.
    let root = AS2Object()

    let objectPrototype: AS2Object
    let functionPrototype: AS2Object
    let arrayPrototype: AS2Object
    let stringPrototype: AS2Object
    let numberPrototype: AS2Object
    let booleanPrototype: AS2Object

    private(set) var tally: AS2Tally
    private(set) var traceLog: AS2TraceLog
    /// Symbol name to constructor, as `Object.registerClass` recorded it.
    private(set) var registeredClasses: [String: AS2Object] = [:]
    private var randomState: UInt64

    /// Registrations kept. A movie that registers more than this is either
    /// generated or malformed; the excess is tallied instead of stored.
    static let registeredClassLimit = 4096

    init(
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
    func execute(_ block: SWFActionBlock, target: AS2Object? = nil) -> AS2ExecutionResult {
        AS2Interpreter(runtime: self).execute(block: block, target: target ?? root)
    }

    /// Runs one DoInitAction (59) stream — the class-registration path.
    @discardableResult
    func execute(_ initAction: SWFDoInitAction, target: AS2Object? = nil) -> AS2ExecutionResult {
        execute(initAction.actions, target: target)
    }

    /// Calls an ActionScript function from the engine. Anything that is not a
    /// function is reported as a completed no-op, so a caller invoking a menu
    /// entry point that a movie never defined does not have to special-case it.
    @discardableResult
    func invoke(
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
    func globalValue(_ name: String) -> AS2Value {
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

    func registeredClass(named symbol: String) -> AS2Object? {
        registeredClasses[symbol]
    }

    /// Registered symbol names, sorted so a report is stable.
    var registeredClassNames: [String] {
        registeredClasses.keys.sorted()
    }

    // MARK: - Object factories

    func makeObject() -> AS2Object {
        AS2Object(prototype: objectPrototype)
    }

    func makeArray(_ elements: [AS2Value] = []) -> AS2Object {
        let array = AS2Object(prototype: arrayPrototype)
        array.markArray(length: 0)
        for (index, element) in elements.enumerated() {
            array.setElement(element, at: index)
        }
        return array
    }

    /// A function object with the `prototype` object every ActionScript
    /// function carries, so `new` and prototype assignment both work.
    func makeFunction(_ callable: AS2Callable) -> AS2Object {
        let function = AS2Object(prototype: functionPrototype)
        function.callable = callable
        let prototype = AS2Object(prototype: objectPrototype)
        prototype.define(.object(function), for: "constructor", flags: .dontEnumerate)
        function.define(.object(prototype), for: "prototype", flags: .dontEnumerate)
        return function
    }

    func makeNative(
        _ name: String,
        _ body: @escaping (AS2CallContext) throws -> AS2Value
    ) -> AS2Object {
        makeFunction(.native(AS2NativeBody(name: name, call: body)))
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

    func noteMissing(_ name: String) {
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

    func noteCall() {
        tally.noteCall()
    }

    func trace(_ message: String) {
        traceLog.append(message)
    }

    func resetDiagnostics() {
        tally = AS2Tally(limits: limits)
        traceLog = AS2TraceLog(limits: limits)
    }

    /// `Math.random`, from a seeded generator so a rendered menu frame is
    /// reproducible. Uses xorshift64*, which needs no dependency and no state
    /// beyond one word.
    func nextRandom() -> Double {
        randomState ^= randomState >> 12
        randomState ^= randomState << 25
        randomState ^= randomState >> 27
        let scrambled = randomState &* 0x2545_F491_4F6C_DD1D
        return Double(scrambled >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
