// Finds the Papyrus natives and condition functions a file registers, and judges each body:
// shallow when it does no work but answer a constant (docs/tools/gaps.md, "Shallow handlers").

import SwiftSyntax

struct Handler: Equatable {
    enum Area: String {
        case native, condition
    }

    let area: Area
    /// `Script.Function` for a native, the Creation Kit name for a condition function.
    let name: String
    let isShallow: Bool
    /// The reason after `Matches the game:` in the comment above the registration.
    let onPurpose: String?
    /// The constant the body answers, as written.
    let answer: String
    let position: AbsolutePosition

    /// Shallow with no name a run can count it by: not on purpose, not a stub, and not a
    /// failure with a reason (gate: `syntax-rules.sh` `unnamed_native_stub`).
    var isUnnamedStub: Bool {
        isShallow && onPurpose == nil && !answer.hasPrefix(".deviated(")
            && !answer.hasPrefix("stub table") && !answer.hasPrefix(".failure(")
    }

    static func == (lhs: Handler, rhs: Handler) -> Bool {
        lhs.row == rhs.row
    }

    var row: String {
        let state = onPurpose != nil ? "on-purpose" : isShallow ? "shallow" : "works"
        return [area.rawValue, name, state, onPurpose ?? answer].joined(separator: "\t")
    }
}

private let purposeMarker = "Matches the game:"

/// Every registration in one file.
func handlers(in tree: SourceFileSyntax) -> [Handler] {
    let finder = RegistrationFinder(viewMode: .sourceAccurate)
    finder.walk(tree)
    let stubFile = finder.answersStubs
    return finder.found + (stubFile ? finder.tableRows : [])
}

private final class RegistrationFinder: SyntaxVisitor {
    var found: [Handler] = []
    /// Calls with two leading name literals and no body: rows of a stub table.
    var tableRows: [Handler] = []
    /// True when a body in the file answers `.deviated(_, .stubbed)`.
    var answersStubs = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if node.trimmedDescription.contains(".stubbed"), node.calledExpression
            .trimmedDescription.hasSuffix("deviated")
        {
            answersStubs = true
        }
        guard let (area, name) = registeredName(node) else { return .visitChildren }
        let purpose = onPurpose(node)
        if let body = node.trailingClosure ?? closureArgument(node) {
            let answer = constantAnswer(body.statements)
            found.append(Handler(
                area: area, name: name, isShallow: answer != nil, onPurpose: purpose,
                answer: answer ?? "", position: node.positionAfterSkippingLeadingTrivia
            ))
        } else if area == .native, node.arguments.count >= 3 {
            let answer = node.arguments.dropFirst(2).first?.expression.trimmedDescription ?? ""
            tableRows.append(Handler(
                area: area, name: name, isShallow: true, onPurpose: purpose,
                answer: "stub table: " + answer, position: node.positionAfterSkippingLeadingTrivia
            ))
        }
        return .visitChildren
    }
}

/// `("Sound", "Play")`, `(scriptName: "Sound", functionName: "Play")`, or a condition
/// function's `(index: 407, name: "GetVATSValue")`. A helper that names only the function,
/// such as `reference("GetDistance") { ... }`, gives `*.GetDistance`.
private func registeredName(_ call: FunctionCallExprSyntax) -> (Handler.Area, String)? {
    let arguments = Array(call.arguments)
    if calleeName(call.calledExpression) == "ConditionFunction" {
        let name = arguments.first { $0.label?.text == "name" }.flatMap { literal($0.expression) }
        return name.map { (.condition, $0) }
    }
    if
        call.trailingClosure != nil, let first = arguments.first, first.label == nil,
        let function = literal(first.expression), isIdentifier(function),
        arguments.count == 1 || literal(arguments[1].expression) == nil
    {
        return (.native, "*.\(function)")
    }
    guard arguments.count >= 2 else { return nil }
    let labels = arguments.prefix(2).map { $0.label?.text }
    guard
        labels == [nil, nil] || labels == ["scriptName", "functionName"],
        let script = literal(arguments[0].expression),
        let function = literal(arguments[1].expression),
        isIdentifier(script), isIdentifier(function)
    else { return nil }
    return (.native, "\(script).\(function)")
}

/// A Papyrus name: a capital letter, then letters and digits.
private func isIdentifier(_ text: String) -> Bool {
    text.first?.isUppercase == true && text.allSatisfy { $0.isLetter || $0.isNumber }
}

private func closureArgument(_ call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
    call.arguments.lazy.compactMap { $0.expression.as(ClosureExprSyntax.self) }.first
}

private func literal(_ expression: ExprSyntax) -> String? {
    guard
        let string = expression.as(StringLiteralExprSyntax.self),
        string.segments.count == 1,
        let segment = string.segments.first?.as(StringSegmentSyntax.self)
    else { return nil }
    return segment.content.text
}

private func calleeName(_ expression: ExprSyntax) -> String? {
    if let reference = expression.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text
    }
    return expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
}

/// The reason in a `// Matches the game: ...` comment on the statement that holds the call.
private func onPurpose(_ call: FunctionCallExprSyntax) -> String? {
    var node: Syntax? = Syntax(call)
    while let current = node {
        let text = current.leadingTrivia.pieces.compactMap { piece -> String? in
            switch piece {
            case let .lineComment(comment), let .docLineComment(comment): comment
            default: nil
            }
        }.joined(separator: " ")
        if let range = text.range(of: purposeMarker) {
            return text[range.upperBound...]
                .replacingOccurrences(of: "//", with: "")
                .split(separator: " ").joined(separator: " ")
        }
        if current.is(CodeBlockItemSyntax.self) || current.is(ArrayElementSyntax.self) {
            return nil
        }
        node = current.parent
    }
    return nil
}

/// The constant a body answers when it does nothing else, or nil when it does work. A log
/// line is no work. An empty body answers nothing, written `()`.
func constantAnswer(_ statements: CodeBlockItemListSyntax) -> String? {
    let work = statements.filter { !isLogLine($0.item) }
    guard let last = work.last else { return "()" }
    guard work.count == 1 else { return nil }
    switch last.item {
    case let .stmt(statement):
        guard let returned = statement.as(ReturnStmtSyntax.self) else { return nil }
        guard let expression = returned.expression else { return "()" }
        return isConstant(expression) ? expression.trimmedDescription : nil
    case let .expr(expression):
        return isConstant(expression) ? expression.trimmedDescription : nil
    default:
        return nil
    }
}

private func isLogLine(_ item: CodeBlockItemSyntax.Item) -> Bool {
    guard case let .expr(expression) = item, let call = expression.as(FunctionCallExprSyntax.self)
    else { return false }
    let callee = call.calledExpression.trimmedDescription.lowercased()
    return callee.contains("log") || callee.hasSuffix(".trace")
}

/// A literal, `nil`, a member such as `.none`, or a call of a member or type name whose
/// arguments are all constant, such as `.returned(.boolean(true))`.
private func isConstant(_ expression: ExprSyntax) -> Bool {
    if expression.is(IntegerLiteralExprSyntax.self) || expression.is(FloatLiteralExprSyntax.self)
        || expression.is(BooleanLiteralExprSyntax.self) || expression.is(NilLiteralExprSyntax.self)
    {
        return true
    }
    if let string = expression.as(StringLiteralExprSyntax.self) {
        return string.segments.allSatisfy { $0.is(StringSegmentSyntax.self) }
    }
    if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
        return isConstant(prefix.expression)
    }
    if let member = expression.as(MemberAccessExprSyntax.self) {
        guard let base = member.base else { return true }
        return calleeName(base)?.first?.isUppercase == true
    }
    if let call = expression.as(FunctionCallExprSyntax.self) {
        guard call.trailingClosure == nil else { return false }
        let callee = call.calledExpression
        let named = callee.as(MemberAccessExprSyntax.self).map { member in
            member.base.map { calleeName($0)?.first?.isUppercase == true } ?? true
        } ?? (calleeName(callee)?.first?.isUppercase == true)
        return named && call.arguments.allSatisfy { isConstant($0.expression) }
    }
    return false
}
