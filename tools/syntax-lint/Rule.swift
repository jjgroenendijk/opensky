// One structural lint rule: the files it reads, and a walk of each file's syntax tree that
// reports the positions it rejects. Comments and string contents are trivia or literal
// segments in the tree, so no rule matches inside them by accident.

import Foundation
import SwiftSyntax

struct Rule {
    let id: String
    let message: String
    /// Files the rule reads, as a regular expression over the repository path.
    var included: String?
    var excluded: String?
    let find: (SourceFileSyntax) -> [AbsolutePosition]

    func applies(to path: String) -> Bool {
        if let included, !Self.matches(included, path) {
            return false
        }
        if let excluded, Self.matches(excluded, path) {
            return false
        }
        return true
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Collects the positions where `check` says yes, for one node type.
final class Finder<Node: SyntaxProtocol>: SyntaxAnyVisitor {
    private let check: (Node) -> Bool
    private(set) var found: [AbsolutePosition] = []

    init(_ check: @escaping (Node) -> Bool) {
        self.check = check
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        if let typed = node.as(Node.self), check(typed) {
            found.append(typed.positionAfterSkippingLeadingTrivia)
        }
        return .visitChildren
    }

    static func run(_ tree: SourceFileSyntax, _ check: @escaping (Node) -> Bool) -> [AbsolutePosition] {
        let finder = Finder(check)
        finder.walk(tree)
        return finder.found
    }
}

/// Positions from several finders, for a rule that looks at more than one node type.
func union(_ parts: [AbsolutePosition]...) -> [AbsolutePosition] {
    parts.flatMap(\.self)
}

// MARK: - Shared reads of the tree

/// The last name of an expression: `renderer` in `game.renderer`, `Foo` in `Foo`.
func lastName(_ expression: ExprSyntax) -> String? {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text
    }
    if let member = expression.as(MemberAccessExprSyntax.self) {
        return member.declName.baseName.text
    }
    if let generic = expression.as(GenericSpecializationExprSyntax.self) {
        return lastName(generic.expression)
    }
    return nil
}

/// `base.name` with a plain base, such as `Task.detached`.
func isMember(_ expression: some SyntaxProtocol, base: String, name: String) -> Bool {
    guard let member = expression.as(MemberAccessExprSyntax.self) else { return false }
    return member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == base
        && member.declName.baseName.text == name
}

func modifierNames(_ modifiers: DeclModifierListSyntax) -> [String] {
    modifiers.map { modifier in
        modifier.detail.map { "\(modifier.name.text)(\($0.detail.text))" } ?? modifier.name.text
    }
}

func hasAttribute(_ attributes: AttributeListSyntax, _ name: String) -> Bool {
    attributes.contains { element in
        element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name
    }
}

/// The parameter name a call site writes first: `world` in `attach(world:)` and in
/// `attach(_ world:)`.
func firstParameterName(_ function: FunctionDeclSyntax) -> String? {
    guard let first = function.signature.parameterClause.parameters.first else { return nil }
    if first.firstName.tokenKind == .wildcard {
        return first.secondName?.text
    }
    return first.firstName.text
}

func containsFunctionType(_ node: some SyntaxProtocol) -> Bool {
    if node.is(FunctionTypeSyntax.self) {
        return true
    }
    return node.children(viewMode: .sourceAccurate).contains { containsFunctionType($0) }
}

/// A stored property: no accessor block, or only `willSet` and `didSet` observers.
func isStored(_ binding: PatternBindingSyntax) -> Bool {
    guard let block = binding.accessorBlock else { return true }
    guard case let .accessors(accessors) = block.accessors else { return false }
    return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
}

func bindingName(_ binding: PatternBindingSyntax) -> String? {
    binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
}
