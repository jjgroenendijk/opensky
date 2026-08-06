// Built-in objects (milestone 8.3.2): only what vanilla class-registration
// code needs — `Object` (with `registerClass` and `addProperty`), `Function`,
// `Array`, `String`, `Number`, `Boolean`, `Math`, `ASSetPropFlags`, and the
// handful of global functions.
//
// `MovieClip`, `TextField`, `Stage`, `Selection`, `EventDispatcher`, and the
// `gfx` framework are deliberately absent. A reference to any of them resolves
// to `undefined` and lands in the tally as a named missing API, which is
// exactly the coverage evidence the next milestone needs.
//
// These are Flash built-ins, not SWF file-format structures, so they are
// reimplemented from the public ActionScript 2 behavior and from ECMA-262 3rd
// edition, section 15 "Native ECMAScript Objects", which ActionScript follows
// for `Object`, `Array`, `String`, `Number`, `Boolean`, and `Math`.

import Foundation

nonisolated enum AS2Natives {
    static func install(into runtime: AS2Runtime) {
        installObject(runtime)
        installFunction(runtime)
        installArray(runtime)
        installString(runtime)
        installNumber(runtime)
        installBoolean(runtime)
        installMath(runtime)
        installGlobals(runtime)
    }

    /// Defines a global constructor bound to an existing prototype object.
    @discardableResult
    static func constructor(
        _ runtime: AS2Runtime,
        name: String,
        prototype: AS2Object,
        body: @escaping (AS2CallContext) throws -> AS2Value
    ) -> AS2Object {
        let function = runtime.makeNative(name, body)
        function.define(.object(prototype), for: "prototype", flags: [.dontEnumerate, .dontDelete])
        prototype.define(.object(function), for: "constructor", flags: .dontEnumerate)
        runtime.globalObject.define(.object(function), for: name, flags: .dontEnumerate)
        return function
    }

    /// Defines a non-enumerable method, the way every Flash built-in member is
    /// declared.
    static func method(
        _ runtime: AS2Runtime,
        on object: AS2Object,
        name: String,
        body: @escaping (AS2CallContext) throws -> AS2Value
    ) {
        object.define(.object(runtime.makeNative(name, body)), for: name, flags: .dontEnumerate)
    }

    // MARK: - Object

    private static func installObject(_ runtime: AS2Runtime) {
        let prototype = runtime.objectPrototype
        method(runtime, on: prototype, name: "toString") { _ in .string("[object Object]") }
        method(runtime, on: prototype, name: "valueOf") { context in context.thisValue }
        method(runtime, on: prototype, name: "hasOwnProperty") { context in
            let name = try context.string(0)
            return .boolean(context.thisObject?.hasOwnProperty(name) ?? false)
        }
        method(runtime, on: prototype, name: "isPropertyEnumerable") { context in
            let name = try context.string(0)
            let property = context.thisObject?.ownProperty(name)
            return .boolean(property.map { !$0.flags.contains(.dontEnumerate) } ?? false)
        }
        method(runtime, on: prototype, name: "isPrototypeOf") { context in
            guard let candidate = context.thisObject, let object = context.argument(0).objectValue
            else {
                return .boolean(false)
            }
            return .boolean(isPrototype(candidate, of: object))
        }
        method(runtime, on: prototype, name: "addProperty") { context in
            try addProperty(context)
        }
        installObjectConstructor(runtime, prototype: prototype)
    }

    private static func installObjectConstructor(_ runtime: AS2Runtime, prototype: AS2Object) {
        let function = constructor(runtime, name: "Object", prototype: prototype) { context in
            if context.isConstructing {
                return .undefined
            }
            let argument = context.argument(0)
            return argument.objectValue == nil ? .object(context.runtime.makeObject()) : argument
        }
        method(runtime, on: function, name: "registerClass") { context in
            let symbol = try context.string(0)
            let target = context.argument(1).functionValue
            return .boolean(context.runtime.registerClass(symbol: symbol, constructor: target))
        }
    }

    private static func addProperty(_ context: AS2CallContext) throws -> AS2Value {
        guard let object = context.thisObject else {
            return .boolean(false)
        }
        let name = try context.string(0)
        guard !name.isEmpty else {
            return .boolean(false)
        }
        let getter = context.argument(1).functionValue
        let setter = context.argument(2).functionValue
        return .boolean(object.addAccessor(name: name, getter: getter, setter: setter))
    }

    private static func isPrototype(_ candidate: AS2Object, of object: AS2Object) -> Bool {
        var current = object.prototype
        var steps = 0
        while let link = current, steps < AS2Object.prototypeChainLimit {
            if link === candidate {
                return true
            }
            current = link.prototype
            steps += 1
        }
        return false
    }

    // MARK: - Function

    private static func installFunction(_ runtime: AS2Runtime) {
        let prototype = runtime.functionPrototype
        method(runtime, on: prototype, name: "toString") { _ in .string("[type Function]") }
        method(runtime, on: prototype, name: "call") { context in
            guard let function = context.thisValue.functionValue else {
                return .undefined
            }
            return try context.interpreter.call(
                function,
                thisValue: context.argument(0),
                arguments: Array(context.arguments.dropFirst()),
                offset: 0
            )
        }
        method(runtime, on: prototype, name: "apply") { context in
            guard let function = context.thisValue.functionValue else {
                return .undefined
            }
            let list = context.argument(1).objectValue?.elements ?? []
            return try context.interpreter.call(
                function, thisValue: context.argument(0), arguments: list, offset: 0
            )
        }
        constructor(runtime, name: "Function", prototype: prototype) { _ in .undefined }
    }

    // MARK: - Globals

    private static func installGlobals(_ runtime: AS2Runtime) {
        let global = runtime.globalObject
        global.define(.object(global), for: "_global", flags: [.dontEnumerate, .dontDelete])
        global.define(.number(.nan), for: "NaN", flags: [.dontEnumerate, .dontDelete])
        global.define(.number(.infinity), for: "Infinity", flags: [.dontEnumerate, .dontDelete])
        global.define(.undefined, for: "undefined", flags: [.dontEnumerate, .dontDelete])
        method(runtime, on: global, name: "ASSetPropFlags") { context in
            try applyPropertyFlags(context)
        }
        method(runtime, on: global, name: "isNaN") { context in
            try .boolean(context.number(0).isNaN)
        }
        method(runtime, on: global, name: "parseInt") { context in
            try .number(AS2NativeNumbers.parseInt(context.string(0), radix: context.number(1)))
        }
        method(runtime, on: global, name: "parseFloat") { context in
            try .number(AS2NativeNumbers.parseFloat(context.string(0)))
        }
    }

    /// `ASSetPropFlags(object, names, setFlags, clearFlags)`. `names` is null
    /// for "every property", a comma-separated string, or an array of names.
    private static func applyPropertyFlags(_ context: AS2CallContext) throws -> AS2Value {
        guard let object = context.argument(0).objectValue else {
            return .undefined
        }
        try object.applyPropertyFlags(
            names: propertyNames(context.argument(1), context: context),
            adding: propertyFlags(context.number(2)),
            removing: propertyFlags(context.number(3))
        )
        return .undefined
    }

    private static func propertyNames(
        _ value: AS2Value,
        context: AS2CallContext
    ) throws -> [String]? {
        if let array = value.objectValue, array.isArray {
            var names: [String] = []
            for element in array.elements {
                try names.append(context.interpreter.toString(element))
            }
            return names
        }
        guard case let .string(text) = value else {
            return nil
        }
        return text.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func propertyFlags(_ value: Double) -> AS2PropertyFlags {
        guard value.isFinite, value >= 0, value < 256 else {
            return []
        }
        return AS2PropertyFlags(rawValue: UInt8(value))
    }
}
