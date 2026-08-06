// The `Array` built-in (milestone 8.3.2).
//
// Reference: ECMA-262 3rd edition, section 15.4 "Array Objects" — the
// constructor's single-numeric-argument form (15.4.2.2) and the prototype
// methods reimplemented here (15.4.4.5 `join`, 15.4.4.6 `pop`, 15.4.4.7 `push`,
// 15.4.4.9 `shift`, 15.4.4.10 `slice`, 15.4.4.13 `unshift`).

import Foundation

nonisolated extension AS2Natives {
    static func installArray(_ runtime: AS2Runtime) {
        let prototype = runtime.arrayPrototype
        prototype.markArray(length: 0)
        installArrayMethods(runtime, on: prototype)
        constructor(runtime, name: "Array", prototype: prototype) { context in
            let array = context.isConstructing
                ? (context.thisObject ?? context.runtime.makeArray())
                : context.runtime.makeArray()
            fill(array, with: context)
            return context.isConstructing ? .undefined : .object(array)
        }
    }

    /// `new Array(5)` allocates a length; `new Array(a, b)` stores elements.
    private static func fill(_ array: AS2Object, with context: AS2CallContext) {
        array.markArray(length: 0)
        if context.arguments.count == 1, case let .number(length) = context.argument(0) {
            array.resizeArray(to: length.isFinite && length > 0 ? Int(min(length, 1e6)) : 0)
            return
        }
        for (index, element) in context.arguments.enumerated() {
            array.setElement(element, at: index)
        }
    }

    private static func installArrayMethods(_ runtime: AS2Runtime, on prototype: AS2Object) {
        method(runtime, on: prototype, name: "push") { context in
            guard let array = context.thisObject else {
                return .undefined
            }
            for element in context.arguments {
                array.appendElement(element)
            }
            return .integer(array.arrayLength ?? 0)
        }
        method(runtime, on: prototype, name: "pop") { context in
            guard let array = context.thisObject, let length = array.arrayLength, length > 0 else {
                return .undefined
            }
            let value = array.element(at: length - 1)
            array.resizeArray(to: length - 1)
            return value
        }
        method(runtime, on: prototype, name: "shift") { context in
            guard let array = context.thisObject, let length = array.arrayLength, length > 0 else {
                return .undefined
            }
            let value = array.element(at: 0)
            replace(array, with: Array(array.elements.dropFirst()))
            return value
        }
        method(runtime, on: prototype, name: "unshift") { context in
            guard let array = context.thisObject else {
                return .undefined
            }
            replace(array, with: context.arguments + array.elements)
            return .integer(array.arrayLength ?? 0)
        }
        installArrayReaders(runtime, on: prototype)
    }

    private static func installArrayReaders(_ runtime: AS2Runtime, on prototype: AS2Object) {
        method(runtime, on: prototype, name: "join") { context in
            try .string(joined(context, separator: context.argument(0)))
        }
        method(runtime, on: prototype, name: "toString") { context in
            try .string(joined(context, separator: .string(",")))
        }
        method(runtime, on: prototype, name: "concat") { context in
            let base = context.thisObject?.elements ?? []
            let extra = context.arguments.flatMap { value -> [AS2Value] in
                guard let object = value.objectValue, object.isArray else {
                    return [value]
                }
                return object.elements
            }
            return .object(context.runtime.makeArray(base + extra))
        }
        method(runtime, on: prototype, name: "slice") { context in
            let elements = context.thisObject?.elements ?? []
            let start = try bound(context.number(0), count: elements.count, fallback: 0)
            var end = elements.count
            if context.arguments.count > 1 {
                end = try bound(context.number(1), count: elements.count, fallback: elements.count)
            }
            let range = start ..< max(start, end)
            return .object(context.runtime.makeArray(Array(elements[range])))
        }
        method(runtime, on: prototype, name: "indexOf") { context in
            let elements = context.thisObject?.elements ?? []
            let needle = context.argument(0)
            return .integer(elements.firstIndex(of: needle) ?? -1)
        }
    }

    private static func joined(
        _ context: AS2CallContext,
        separator: AS2Value
    ) throws -> String {
        var text = ","
        if separator != .undefined {
            text = try context.interpreter.toString(separator)
        }
        var parts: [String] = []
        for element in context.thisObject?.elements ?? [] {
            switch element {
            case .undefined, .null:
                parts.append("")
            default:
                try parts.append(context.interpreter.toString(element))
            }
        }
        return parts.joined(separator: text)
    }

    private static func replace(_ array: AS2Object, with elements: [AS2Value]) {
        array.resizeArray(to: 0)
        for (index, element) in elements.enumerated() {
            array.setElement(element, at: index)
        }
    }

    /// ECMA-262 15.4.4.10: a negative index counts back from the end, and every
    /// index clamps into `0...count`.
    private static func bound(_ value: Double, count: Int, fallback: Int) -> Int {
        guard value.isFinite else {
            return fallback
        }
        let index = Int(max(-1e9, min(1e9, value)))
        return index < 0 ? max(0, count + index) : min(index, count)
    }
}
