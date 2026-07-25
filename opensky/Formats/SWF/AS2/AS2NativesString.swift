// The `String` built-in (milestone 8.3.2). ActionScript strings index by UTF-16
// code unit, so every offset here is a `String.UTF16View` offset rather than a
// Swift `Character` offset — a menu string with an accented glyph would
// otherwise report a different `length` than Flash does.
//
// Reference: ECMA-262 3rd edition, section 15.5 "String Objects" — 15.5.4.4
// `charAt`, 15.5.4.5 `charCodeAt`, 15.5.4.7 `indexOf`, 15.5.4.8 `lastIndexOf`,
// 15.5.4.13 `slice`, 15.5.4.14 `split`, 15.5.4.15 `substring`, and the
// ActionScript-only `substr`.

import Foundation

extension AS2Natives {
    static func installString(_ runtime: AS2Runtime) {
        let prototype = runtime.stringPrototype
        installStringReaders(runtime, on: prototype)
        installStringSlicers(runtime, on: prototype)
        let function = constructor(runtime, name: "String", prototype: prototype) { context in
            guard !context.arguments.isEmpty else {
                return .string("")
            }
            return try .string(context.string(0))
        }
        method(runtime, on: function, name: "fromCharCode") { context in
            var text = ""
            for argument in context.arguments {
                let code = try context.interpreter.toNumber(argument)
                guard
                    code.isFinite, code >= 0, code < 0x10000,
                    let scalar = Unicode.Scalar(UInt16(code))
                else {
                    continue
                }
                text.append(Character(scalar))
            }
            return .string(text)
        }
    }

    private static func installStringReaders(_ runtime: AS2Runtime, on prototype: AS2Object) {
        method(runtime, on: prototype, name: "toString") { context in
            try .string(context.interpreter.toString(context.thisValue))
        }
        method(runtime, on: prototype, name: "valueOf") { context in context.thisValue }
        method(runtime, on: prototype, name: "charAt") { context in
            let units = try receiverUnits(context)
            let index = try indexArgument(context, at: 0)
            guard index >= 0, index < units.count else {
                return .string("")
            }
            return .string(text(from: [units[index]]))
        }
        method(runtime, on: prototype, name: "charCodeAt") { context in
            let units = try receiverUnits(context)
            let index = try indexArgument(context, at: 0)
            guard index >= 0, index < units.count else {
                return .number(.nan)
            }
            return .integer(Int(units[index]))
        }
        method(runtime, on: prototype, name: "toLowerCase") { context in
            try .string(receiverText(context).lowercased())
        }
        method(runtime, on: prototype, name: "toUpperCase") { context in
            try .string(receiverText(context).uppercased())
        }
        method(runtime, on: prototype, name: "indexOf") { context in
            let units = try receiverUnits(context)
            let needle = try Array(context.string(0).utf16)
            var start = 0
            if context.arguments.count > 1 {
                start = try indexArgument(context, at: 1)
            }
            return .integer(search(units, needle, from: max(0, start), reverse: false))
        }
        method(runtime, on: prototype, name: "lastIndexOf") { context in
            let units = try receiverUnits(context)
            let needle = try Array(context.string(0).utf16)
            return .integer(search(units, needle, from: 0, reverse: true))
        }
    }

    private static func installStringSlicers(_ runtime: AS2Runtime, on prototype: AS2Object) {
        method(runtime, on: prototype, name: "substring") { context in
            let units = try receiverUnits(context)
            var start = try clamp(context.number(0), count: units.count)
            var end = units.count
            if context.arguments.count > 1 {
                end = try clamp(context.number(1), count: units.count)
            }
            if start > end {
                swap(&start, &end)
            }
            return .string(text(from: Array(units[start ..< end])))
        }
        method(runtime, on: prototype, name: "slice") { context in
            let units = try receiverUnits(context)
            let start = try relative(context, at: 0, count: units.count, fallback: 0)
            var end = units.count
            if context.arguments.count > 1 {
                end = try relative(context, at: 1, count: units.count, fallback: units.count)
            }
            return .string(text(from: Array(units[start ..< max(start, end)])))
        }
        method(runtime, on: prototype, name: "substr") { context in
            let units = try receiverUnits(context)
            let start = try relative(context, at: 0, count: units.count, fallback: 0)
            var length = units.count - start
            if context.arguments.count > 1 {
                let requested = try context.number(1)
                length = requested.isFinite ? Int(max(0, min(requested, 1e6))) : 0
            }
            let end = min(units.count, start + max(0, length))
            return .string(text(from: Array(units[start ..< max(start, end)])))
        }
        method(runtime, on: prototype, name: "split") { context in
            let source = try receiverText(context)
            let separator = try context.string(0)
            let parts = separator.isEmpty
                ? source.map(String.init)
                : source.components(separatedBy: separator)
            return .object(context.runtime.makeArray(parts.map(AS2Value.string)))
        }
    }

    private static func receiverText(_ context: AS2CallContext) throws -> String {
        try context.interpreter.toString(context.thisValue)
    }

    private static func receiverUnits(_ context: AS2CallContext) throws -> [UInt16] {
        try Array(receiverText(context).utf16)
    }

    private static func text(from units: [UInt16]) -> String {
        String(decoding: units, as: UTF16.self)
    }

    private static func indexArgument(
        _ context: AS2CallContext,
        at index: Int
    ) throws -> Int {
        let value = try context.number(index)
        guard value.isFinite else {
            return -1
        }
        return Int(max(-1e9, min(1e9, value)))
    }

    private static func relative(
        _ context: AS2CallContext,
        at index: Int,
        count: Int,
        fallback: Int
    ) throws -> Int {
        let value = try context.number(index)
        guard value.isFinite else {
            return fallback
        }
        let position = Int(max(-1e9, min(1e9, value)))
        return position < 0 ? max(0, count + position) : min(position, count)
    }

    private static func clamp(_ value: Double, count: Int) -> Int {
        guard value.isFinite, value > 0 else {
            return 0
        }
        return min(Int(min(value, 1e9)), count)
    }

    private static func search(
        _ units: [UInt16],
        _ needle: [UInt16],
        from start: Int,
        reverse: Bool
    ) -> Int {
        guard !needle.isEmpty, needle.count <= units.count else {
            return needle.isEmpty ? min(start, units.count) : -1
        }
        let positions = 0 ... (units.count - needle.count)
        let candidates = reverse ? Array(positions.reversed()) : Array(positions)
        for position in candidates where position >= start {
            if Array(units[position ..< position + needle.count]) == needle {
                return position
            }
        }
        return -1
    }
}
