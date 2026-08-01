// The `Number`, `Boolean`, and `Math` built-ins, plus the numeric parsing the
// global `parseInt`/`parseFloat` use (milestone 8.3.2).
//
// `Math.random` draws from the runtime's seeded generator rather than the
// system one, so a menu that animates on random values still renders the same
// frame twice — the rendering layer's determinism contract (docs/rendering/ui.md).
//
// Reference: ECMA-262 3rd edition, section 15.7 "Number Objects", section 15.6
// "Boolean Objects", section 15.8 "The Math Object", and sections 15.1.2.2
// `parseInt` and 15.1.2.3 `parseFloat`.

import Foundation

nonisolated extension AS2Natives {
    static func installNumber(_ runtime: AS2Runtime) {
        let prototype = runtime.numberPrototype
        method(runtime, on: prototype, name: "valueOf") { context in context.thisValue }
        method(runtime, on: prototype, name: "toString") { context in
            try .string(context.interpreter.toString(context.thisValue))
        }
        let function = constructor(runtime, name: "Number", prototype: prototype) { context in
            guard !context.arguments.isEmpty else {
                return .number(0)
            }
            return try .number(context.number(0))
        }
        function.define(.number(.greatestFiniteMagnitude), for: "MAX_VALUE", flags: .dontEnumerate)
        function.define(.number(.leastNonzeroMagnitude), for: "MIN_VALUE", flags: .dontEnumerate)
        function.define(.number(.nan), for: "NaN", flags: .dontEnumerate)
        function.define(.number(.infinity), for: "POSITIVE_INFINITY", flags: .dontEnumerate)
        function.define(.number(-.infinity), for: "NEGATIVE_INFINITY", flags: .dontEnumerate)
    }

    static func installBoolean(_ runtime: AS2Runtime) {
        let prototype = runtime.booleanPrototype
        method(runtime, on: prototype, name: "valueOf") { context in context.thisValue }
        method(runtime, on: prototype, name: "toString") { context in
            try .string(context.interpreter.toString(context.thisValue))
        }
        constructor(runtime, name: "Boolean", prototype: prototype) { context in
            .boolean(context.boolean(0))
        }
    }

    static func installMath(_ runtime: AS2Runtime) {
        let math = runtime.makeObject()
        math.define(.number(Double.pi), for: "PI", flags: [.dontEnumerate, .readOnly])
        math.define(.number(M_E), for: "E", flags: [.dontEnumerate, .readOnly])
        math.define(.number(log2(M_E)), for: "LOG2E", flags: [.dontEnumerate, .readOnly])
        math.define(.number(log10(M_E)), for: "LOG10E", flags: [.dontEnumerate, .readOnly])
        math.define(.number(2.0.squareRoot()), for: "SQRT2", flags: [.dontEnumerate, .readOnly])
        installUnaryMath(runtime, on: math)
        installBinaryMath(runtime, on: math)
        method(runtime, on: math, name: "random") { context in
            .number(context.runtime.nextRandom())
        }
        runtime.globalObject.define(.object(math), for: "Math", flags: .dontEnumerate)
    }

    private static func installUnaryMath(_ runtime: AS2Runtime, on math: AS2Object) {
        let unary: [String: (Double) -> Double] = [
            "abs": { abs($0) }, "ceil": { $0.rounded(.up) }, "floor": { $0.rounded(.down) },
            "sqrt": { $0 < 0 ? Double.nan : $0.squareRoot() }, "sin": sin, "cos": cos,
            "tan": tan, "asin": asin, "acos": acos, "atan": atan, "exp": exp,
            "log": { $0 < 0 ? Double.nan : log($0) }
        ]
        for name in unary.keys.sorted() {
            guard let operation = unary[name] else {
                continue
            }
            method(runtime, on: math, name: name) { context in
                try .number(operation(context.number(0)))
            }
        }
        // ECMAScript rounds halfway cases toward positive infinity, which
        // `Double.rounded()` does not: it rounds away from zero.
        method(runtime, on: math, name: "round") { context in
            let value = try context.number(0)
            return .number(value.isFinite ? (value + 0.5).rounded(.down) : value)
        }
    }

    private static func installBinaryMath(_ runtime: AS2Runtime, on math: AS2Object) {
        method(runtime, on: math, name: "pow") { context in
            try .number(pow(context.number(0), context.number(1)))
        }
        method(runtime, on: math, name: "atan2") { context in
            try .number(atan2(context.number(0), context.number(1)))
        }
        method(runtime, on: math, name: "max") { context in
            try .number(extremum(context, keepingGreater: true))
        }
        method(runtime, on: math, name: "min") { context in
            try .number(extremum(context, keepingGreater: false))
        }
    }

    /// ECMA-262 15.8.2.11/15.8.2.12: no arguments yields the identity infinity,
    /// and any NaN argument poisons the result.
    private static func extremum(
        _ context: AS2CallContext,
        keepingGreater: Bool
    ) throws -> Double {
        var result = keepingGreater ? -Double.infinity : Double.infinity
        for index in context.arguments.indices {
            let value = try context.number(index)
            if value.isNaN {
                return .nan
            }
            result = keepingGreater ? Swift.max(result, value) : Swift.min(result, value)
        }
        return result
    }
}

/// Numeric parsing for the global `parseInt` and `parseFloat`.
nonisolated enum AS2NativeNumbers {
    /// ECMA-262 15.1.2.2. An explicit radix wins; otherwise a `0x` prefix means
    /// 16 and everything else means 10.
    static func parseInt(_ text: String, radix: Double) -> Double {
        var body = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var sign = 1.0
        if body.hasPrefix("-") {
            sign = -1
            body = body.dropFirst()
        } else if body.hasPrefix("+") {
            body = body.dropFirst()
        }
        var base = 10
        if radix.isFinite, radix >= 2, radix <= 36 {
            base = Int(radix)
        }
        if base == 16 || !radix.isFinite || radix == 0 {
            if body.hasPrefix("0x") || body.hasPrefix("0X") {
                body = body.dropFirst(2)
                base = 16
            }
        }
        let digits = body.prefix { character in
            guard let value = character.hexDigitValue else {
                return false
            }
            return value < base
        }
        guard !digits.isEmpty, let value = Int64(digits, radix: base) else {
            return .nan
        }
        return sign * Double(value)
    }

    /// ECMA-262 15.1.2.3: the longest prefix that is a decimal literal.
    static func parseFloat(_ text: String) -> Double {
        let trimmed = Substring(
            text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(scanLimit)
        )
        var best = Double.nan
        var index = trimmed.startIndex
        while index <= trimmed.endIndex {
            let candidate = trimmed[trimmed.startIndex ..< index]
            if let value = literalValue(candidate) {
                best = value
            }
            guard index < trimmed.endIndex else {
                break
            }
            index = trimmed.index(after: index)
        }
        return best
    }

    /// Longest prefix `parseFloat` examines. A number literal never needs more,
    /// and the scan is quadratic in the prefix length.
    static let scanLimit = 64

    private static func literalValue(_ text: Substring) -> Double? {
        var body = text
        var sign = 1.0
        if body.hasPrefix("-") {
            sign = -1
            body = body.dropFirst()
        } else if body.hasPrefix("+") {
            body = body.dropFirst()
        }
        if body == "Infinity" {
            return sign * .infinity
        }
        guard AS2Coercion.isDecimalLiteral(body), let magnitude = Double(body) else {
            return nil
        }
        return sign * magnitude
    }
}
