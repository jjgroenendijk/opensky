// The statements an `hkbEvaluateExpressionModifier` runs. The grammar comes from the
// vanilla strings: `turnSpeedMult = fabs(TurnDelta/90)` assigns a variable, and
// `weaponDraw if (iCombatStance == 1)` raises an event. Values are floats; a
// comparison or logic operator gives 1 or 0. Docs: docs/engine/behavior-runtime.md.

import Foundation

/// One parsed statement.
nonisolated public enum BehaviorExpressionStatement: Equatable, Sendable {
    case assignment(variable: String, value: BehaviorExpression)
    case event(name: String, condition: BehaviorExpression)

    /// Parses `source`, or nil when it fits neither statement form.
    public static func parse(_ source: String) -> BehaviorExpressionStatement? {
        guard
            let tokens = BehaviorExpressionLexer.tokens(of: source), tokens.count >= 3,
            case let .name(target) = tokens[0] else { return nil }
        let rest = Array(tokens.dropFirst(2))
        switch tokens[1] {
        case .assign:
            return BehaviorExpression.parse(rest).map { .assignment(variable: target, value: $0) }
        case .name("if"):
            return BehaviorExpression.parse(rest).map { .event(name: target, condition: $0) }
        default:
            return nil
        }
    }
}

/// One parsed arithmetic expression.
indirect nonisolated public enum BehaviorExpression: Equatable, Sendable {
    case number(Float)
    case variable(String)
    case unary(String, BehaviorExpression)
    case binary(String, BehaviorExpression, BehaviorExpression)
    case call(String, [BehaviorExpression])

    static func parse(_ tokens: [BehaviorExpressionToken]) -> BehaviorExpression? {
        var parser = BehaviorExpressionParser(tokens: tokens)
        guard let root = parser.parse(level: 0), parser.isAtEnd else { return nil }
        return root
    }

    /// The value, or nil when a name does not resolve or a function is unknown.
    public func evaluate(_ lookup: (String) -> Float?) -> Float? {
        switch self {
        case let .number(value):
            return value
        case let .variable(name):
            return lookup(name)
        case let .unary(symbol, operand):
            guard let value = operand.evaluate(lookup) else { return nil }
            return symbol == "!" ? (value == 0 ? 1 : 0) : -value
        case let .binary(symbol, lhs, rhs):
            guard let left = lhs.evaluate(lookup), let right = rhs.evaluate(lookup) else {
                return nil
            }
            return Self.apply(symbol, left, right)
        case let .call(name, arguments):
            let values = arguments.compactMap { $0.evaluate(lookup) }
            guard values.count == arguments.count else { return nil }
            return BehaviorExpressionFunctions.call(name, values)
        }
    }

    private static func apply(_ symbol: String, _ left: Float, _ right: Float) -> Float? {
        switch symbol {
        case "+": left + right
        case "-": left - right
        case "*": left * right
        case "/": right == 0 ? 0 : left / right
        case "%": right == 0 ? 0 : fmodf(left, right)
        case "&&": left != 0 && right != 0 ? 1 : 0
        case "||": left != 0 || right != 0 ? 1 : 0
        default: compare(symbol, left, right).map { $0 ? 1 : 0 }
        }
    }

    private static func compare(_ symbol: String, _ left: Float, _ right: Float) -> Bool? {
        switch symbol {
        case "==": left == right
        case "!=": left != right
        case "<": left < right
        case "<=": left <= right
        case ">": left > right
        case ">=": left >= right
        default: nil
        }
    }
}

/// The functions the vanilla expressions call, and the usual neighbours.
/// Names ending in `d` take degrees.
nonisolated enum BehaviorExpressionFunctions {
    static let unary: [String: @Sendable (Float) -> Float] = [
        "abs": abs, "fabs": abs, "sqrt": { sqrtf(max($0, 0)) }, "floor": floorf, "ceil": ceilf,
        "round": roundf, "exp": expf, "log": { $0 > 0 ? logf($0) : 0 },
        "sin": sinf, "cos": cosf, "tan": tanf, "asin": { asinf(min(max($0, -1), 1)) },
        "acos": { acosf(min(max($0, -1), 1)) }, "atan": atanf,
        "sind": { sinf($0 * .pi / 180) }, "cosd": { cosf($0 * .pi / 180) },
        "tand": { tanf($0 * .pi / 180) }, "sign": { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) }
    ]

    static func call(_ name: String, _ values: [Float]) -> Float? {
        if values.count == 1, let function = unary[name.lowercased()] {
            return function(values[0])
        }
        switch (name.lowercased(), values.count) {
        case ("cond", 3): return values[0] != 0 ? values[1] : values[2]
        case ("clamp", 3): return min(max(values[0], values[1]), values[2])
        case ("min", 2): return min(values[0], values[1])
        case ("max", 2): return max(values[0], values[1])
        case ("pow", 2): return powf(values[0], values[1])
        case ("atan2", 2): return atan2f(values[0], values[1])
        default: return nil
        }
    }
}

nonisolated enum BehaviorExpressionToken: Equatable, Sendable {
    case number(Float)
    case name(String)
    case symbol(String)
    case assign
    case open
    case close
    case comma
}

nonisolated enum BehaviorExpressionLexer {
    private static let symbols = [
        "&&",
        "||",
        "==",
        "!=",
        ">=",
        "<=",
        "<",
        ">",
        "+",
        "-",
        "*",
        "/",
        "%",
        "!"
    ]

    static func tokens(of source: String) -> [BehaviorExpressionToken]? {
        let characters = Array(source)
        var tokens: [BehaviorExpressionToken] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if isNameCharacter(character) {
                tokens.append(word(characters, &index))
            } else if let token = punctuation(characters, &index) {
                tokens.append(token)
            } else {
                return nil
            }
        }
        return tokens
    }

    /// A run of name characters: a number when it reads as one, else a name.
    /// Names may start with a digit (`1stPRot`) or hold dots (`SoundPlay.X`).
    private static func word(
        _ characters: [Character],
        _ index: inout Int
    ) -> BehaviorExpressionToken {
        let start = index
        while index < characters.count, isNameCharacter(characters[index]) {
            index += 1
        }
        let text = String(characters[start ..< index])
        return Float(text).map { .number($0) } ?? .name(text)
    }

    private static func punctuation(
        _ characters: [Character], _ index: inout Int
    ) -> BehaviorExpressionToken? {
        let rest = String(characters[index ..< min(index + 2, characters.count)])
        if let symbol = symbols.first(where: rest.hasPrefix) {
            index += symbol.count
            return .symbol(symbol)
        }
        index += 1
        switch characters[index - 1] {
        case "=": return .assign
        case "(": return .open
        case ")": return .close
        case ",": return .comma
        default: return nil
        }
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "."
    }
}

/// Precedence climbing over the binary operators, loosest first.
nonisolated struct BehaviorExpressionParser {
    private static let levels: [[String]] = [
        ["||"], ["&&"], ["==", "!="], ["<", "<=", ">", ">="], ["+", "-"], ["*", "/", "%"]
    ]

    let tokens: [BehaviorExpressionToken]
    private var index = 0

    init(tokens: [BehaviorExpressionToken]) {
        self.tokens = tokens
    }

    var isAtEnd: Bool {
        index == tokens.count
    }

    mutating func parse(level: Int) -> BehaviorExpression? {
        guard level < Self.levels.count else { return parseUnary() }
        guard var lhs = parse(level: level + 1) else { return nil }
        while
            index < tokens.count, case let .symbol(symbol) = tokens[index],
            Self.levels[level].contains(symbol)
        {
            index += 1
            guard let rhs = parse(level: level + 1) else { return nil }
            lhs = .binary(symbol, lhs, rhs)
        }
        return lhs
    }

    private mutating func parseUnary() -> BehaviorExpression? {
        if
            index < tokens.count, case let .symbol(symbol) = tokens[index],
            symbol == "!" || symbol == "-"
        {
            index += 1
            return parseUnary().map { .unary(symbol, $0) }
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> BehaviorExpression? {
        guard index < tokens.count else { return nil }
        let token = tokens[index]
        index += 1
        switch token {
        case let .number(value):
            return .number(value)
        case let .name(name):
            guard index < tokens.count, tokens[index] == .open else { return .variable(name) }
            index += 1
            return parseArguments().map { .call(name, $0) }
        case .open:
            guard let inner = parse(level: 0), index < tokens.count, tokens[index] == .close
            else { return nil }
            index += 1
            return inner
        case .symbol, .assign, .close, .comma:
            return nil
        }
    }

    private mutating func parseArguments() -> [BehaviorExpression]? {
        var arguments: [BehaviorExpression] = []
        if index < tokens.count, tokens[index] == .close {
            index += 1
            return arguments
        }
        while true {
            guard let argument = parse(level: 0), index < tokens.count else { return nil }
            arguments.append(argument)
            let separator = tokens[index]
            index += 1
            if separator == .close {
                return arguments
            }
            guard separator == .comma else { return nil }
        }
    }
}

/// SplitMix64: small, fast, and the same sequence on every machine.
nonisolated public struct BehaviorRandom: Equatable, Sendable {
    private var state: UInt64

    public init(seed: UInt64 = 0x5EED) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// A whole number in `range`.
    public mutating func next(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
}
