// Transition conditions: the expression text an `hkbExpressionCondition` or
// `hkbStringCondition` carries. The grammar comes from the vanilla strings, for
// example `(iWantBlock == 0) || (iLeftHandType == 7)`: `||`, `&&`, comparisons,
// `!`, numbers, variables, and parentheses. A bare variable is true when
// non-zero. An undeclared name fails evaluation
// (`docs/engine/behavior-state-machines.md`).

import Foundation

/// One parsed transition condition. Immutable, so the evaluator parses each
/// authored string once and reuses the tree.
nonisolated public struct BehaviorConditionExpression: Equatable, Sendable {
    /// The comparisons the authored strings use.
    public enum Comparison: String, Equatable, Sendable {
        case equal = "=="
        case notEqual = "!="
        case greaterOrEqual = ">="
        case lessOrEqual = "<="
        case greater = ">"
        case less = "<"

        /// Longest first, so `>=` is not read as `>` followed by `=`.
        public static let allSpellings = ["==", "!=", ">=", "<=", ">", "<"]

        public func holds(_ lhs: Float, _ rhs: Float) -> Bool {
            switch self {
            case .equal: lhs == rhs
            case .notEqual: lhs != rhs
            case .greaterOrEqual: lhs >= rhs
            case .lessOrEqual: lhs <= rhs
            case .greater: lhs > rhs
            case .less: lhs < rhs
            }
        }
    }

    indirect public enum Node: Equatable, Sendable {
        case number(Float)
        case variable(String)
        case negation(Node)
        case comparison(Node, Comparison, Node)
        case conjunction(Node, Node)
        case disjunction(Node, Node)
    }

    public let root: Node

    /// Parses `source`, or returns nil when it is empty or does not fit the
    /// grammar above. Never throws and never traps: the text is external input.
    public static func parse(_ source: String) -> BehaviorConditionExpression? {
        guard let tokens = BehaviorConditionLexer.tokens(of: source) else { return nil }
        var parser = BehaviorConditionParser(tokens: tokens)
        guard let root = parser.parseDisjunction(), parser.isAtEnd else { return nil }
        return BehaviorConditionExpression(root: root)
    }

    /// True or false when every name resolves, nil when one does not.
    public func evaluate(in variables: BehaviorVariableStore) -> Bool? {
        Self.truth(of: root, in: variables)
    }

    private static func truth(of node: Node, in variables: BehaviorVariableStore) -> Bool? {
        switch node {
        case let .negation(inner):
            return truth(of: inner, in: variables).map { !$0 }
        case let .comparison(lhs, comparison, rhs):
            guard
                let left = value(of: lhs, in: variables),
                let right = value(of: rhs, in: variables)
            else {
                return nil
            }
            return comparison.holds(left, right)
        case let .conjunction(lhs, rhs):
            guard let left = truth(of: lhs, in: variables) else { return nil }
            guard left else { return false }
            return truth(of: rhs, in: variables)
        case let .disjunction(lhs, rhs):
            guard let left = truth(of: lhs, in: variables) else { return nil }
            guard !left else { return true }
            return truth(of: rhs, in: variables)
        case .number, .variable:
            return value(of: node, in: variables).map { $0 != 0 }
        }
    }

    private static func value(of node: Node, in variables: BehaviorVariableStore) -> Float? {
        switch node {
        case let .number(value):
            value
        case let .variable(name):
            variables.value(of: name)?.realValue
        case .negation, .comparison, .conjunction, .disjunction:
            truth(of: node, in: variables).map { $0 ? 1 : 0 }
        }
    }
}

/// One lexed token. Split out so the parser reads as grammar rather than as
/// character handling.
nonisolated public enum BehaviorConditionToken: Equatable, Sendable {
    case number(Float)
    case name(String)
    case comparison(BehaviorConditionExpression.Comparison)
    case and
    case or
    case not
    case open
    case close
}

/// Text to tokens. Returns nil on any character the grammar has no place for,
/// so an unexpected authored form is reported rather than half-read.
nonisolated public enum BehaviorConditionLexer: Sendable {
    public static func tokens(of source: String) -> [BehaviorConditionToken]? {
        var tokens: [BehaviorConditionToken] = []
        let characters = Array(source)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if let token = symbol(characters, &index) {
                tokens.append(token)
                continue
            }
            if character.isNumber || character == "." {
                guard let token = number(characters, &index) else { return nil }
                tokens.append(token)
                continue
            }
            if character.isLetter || character == "_" {
                tokens.append(name(characters, &index))
                continue
            }
            return nil
        }
        return tokens.isEmpty ? nil : tokens
    }

    /// One operator or bracket. `&&` and `||` are the only spellings the
    /// authored data uses for the logical operators; single `&` and `|` are not
    /// accepted, because guessing at a bitwise reading would invent semantics.
    private static func symbol(
        _ characters: [Character],
        _ index: inout Int
    ) -> BehaviorConditionToken? {
        let rest = characters[index...]
        for spelling in BehaviorConditionExpression.Comparison.allSpellings {
            guard rest.starts(with: Array(spelling)) else { continue }
            index += spelling.count
            return BehaviorConditionExpression.Comparison(rawValue: spelling).map {
                .comparison($0)
            }
        }
        if rest.starts(with: ["&", "&"]) {
            index += 2
            return .and
        }
        if rest.starts(with: ["|", "|"]) {
            index += 2
            return .or
        }
        switch characters[index] {
        case "!":
            index += 1
            return .not
        case "(":
            index += 1
            return .open
        case ")":
            index += 1
            return .close
        default:
            return nil
        }
    }

    private static func number(
        _ characters: [Character],
        _ index: inout Int
    ) -> BehaviorConditionToken? {
        var text = ""
        while index < characters.count, characters[index].isNumber || characters[index] == "." {
            text.append(characters[index])
            index += 1
        }
        return Float(text).map { .number($0) }
    }

    private static func name(
        _ characters: [Character],
        _ index: inout Int
    ) -> BehaviorConditionToken {
        var text = ""
        while index < characters.count, isNameCharacter(characters[index]) {
            text.append(characters[index])
            index += 1
        }
        return .name(text)
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

/// Recursive descent over the token list. Every rule returns nil rather than
/// throwing, because a malformed condition is data, not a programming error.
nonisolated public struct BehaviorConditionParser: Sendable {
    public let tokens: [BehaviorConditionToken]
    private var index = 0

    public init(tokens: [BehaviorConditionToken]) {
        self.tokens = tokens
    }

    public var isAtEnd: Bool {
        index >= tokens.count
    }

    public mutating func parseDisjunction() -> BehaviorConditionExpression.Node? {
        guard var node = parseConjunction() else { return nil }
        while match(.or) {
            guard let right = parseConjunction() else { return nil }
            node = .disjunction(node, right)
        }
        return node
    }

    private mutating func parseConjunction() -> BehaviorConditionExpression.Node? {
        guard var node = parseComparison() else { return nil }
        while match(.and) {
            guard let right = parseComparison() else { return nil }
            node = .conjunction(node, right)
        }
        return node
    }

    private mutating func parseComparison() -> BehaviorConditionExpression.Node? {
        guard let node = parseUnary() else { return nil }
        guard
            index < tokens.count,
            case let .comparison(comparison) = tokens[index]
        else {
            return node
        }
        index += 1
        guard let right = parseUnary() else { return nil }
        return .comparison(node, comparison, right)
    }

    private mutating func parseUnary() -> BehaviorConditionExpression.Node? {
        guard match(.not) else { return parsePrimary() }
        return parseUnary().map { .negation($0) }
    }

    private mutating func parsePrimary() -> BehaviorConditionExpression.Node? {
        guard index < tokens.count else { return nil }
        let token = tokens[index]
        index += 1
        switch token {
        case let .number(value):
            return .number(value)
        case let .name(name):
            return .variable(name)
        case .open:
            guard let inner = parseDisjunction(), match(.close) else { return nil }
            return inner
        case .comparison, .and, .or, .not, .close:
            return nil
        }
    }

    private mutating func match(_ token: BehaviorConditionToken) -> Bool {
        guard index < tokens.count, tokens[index] == token else { return false }
        index += 1
        return true
    }
}
