// Reads every protocol and protocol extension under src/Sources, so a fake can list the
// requirements a port inherits and skip the ones an extension already answers.

import Foundation
import SwiftParser
import SwiftSyntax

struct ProtocolInfo {
    let name: String
    let file: String

    var module: String {
        URL(fileURLWithPath: file).deletingLastPathComponent().pathComponents
            .drop(while: { $0 != "Sources" }).dropFirst().first ?? ""
    }

    let declaration: ProtocolDeclSyntax
    let imports: [String]

    var inherited: [String] {
        declaration.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
    }
}

/// Every protocol by name, and the member keys each protocol's extensions implement.
struct ProtocolIndex {
    private(set) var protocols: [String: ProtocolInfo] = [:]
    /// Each top-level type name and the modules that declare it.
    private(set) var typeModules: [String: Set<String>] = [:]
    /// Keyed by protocol name and the module of the extension, because a fake sees only
    /// the extensions of the modules it imports.
    private(set) var defaults: [String: [String: Set<String>]] = [:]

    init(sources: URL) throws {
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        for url in files.sorted(by: { $0.path < $1.path }) {
            let tree = Parser.parse(source: try String(contentsOf: url, encoding: .utf8))
            let imports = tree.statements.compactMap { $0.item.as(ImportDeclSyntax.self) }
                .map { $0.path.trimmedDescription }
            let module = url.deletingLastPathComponent().pathComponents
                .drop(while: { $0 != "Sources" }).dropFirst().first ?? ""
            for statement in tree.statements {
                if let name = typeName(statement.item) {
                    typeModules[name, default: []].insert(module)
                }
                if let declaration = statement.item.as(ProtocolDeclSyntax.self) {
                    let name = declaration.name.text
                    protocols[name] = ProtocolInfo(
                        name: name, file: url.path, declaration: declaration, imports: imports
                    )
                } else if let ext = statement.item.as(ExtensionDeclSyntax.self) {
                    let name = ext.extendedType.trimmedDescription
                    for member in ext.memberBlock.members {
                        if let key = memberKey(member.decl) {
                            defaults[name, default: [:]][module, default: []].insert(key)
                        }
                    }
                }
            }
        }
    }

    /// The protocol and each protocol it inherits, nearest first, without repeats.
    func lineage(of name: String) -> [ProtocolInfo] {
        var seen: Set<String> = []
        var order: [ProtocolInfo] = []
        var queue = [name]
        while let next = queue.first {
            queue.removeFirst()
            guard !seen.contains(next), let info = protocols[next] else { continue }
            seen.insert(next)
            order.append(info)
            queue += info.inherited
        }
        return order
    }
}

/// `name(label:label:)` for a function, `name` for a property.
func memberKey(_ declaration: DeclSyntax) -> String? {
    if let function = declaration.as(FunctionDeclSyntax.self) {
        let labels = function.signature.parameterClause.parameters.map {
            "\($0.firstName.text):\($0.type.trimmedDescription),"
        }
        return "\(function.name.text)(\(labels.joined()))"
    }
    if let variable = declaration.as(VariableDeclSyntax.self),
       let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)
    {
        return name.identifier.text
    }
    return nil
}

func typeName(_ item: CodeBlockItemSyntax.Item) -> String? {
    if let type = item.as(StructDeclSyntax.self) { return type.name.text }
    if let type = item.as(ClassDeclSyntax.self) { return type.name.text }
    if let type = item.as(EnumDeclSyntax.self) { return type.name.text }
    if let type = item.as(ActorDeclSyntax.self) { return type.name.text }
    if let type = item.as(ProtocolDeclSyntax.self) { return type.name.text }
    if let type = item.as(TypeAliasDeclSyntax.self) { return type.name.text }
    return nil
}

/// The Apple module of a type name the package does not declare.
func appleModule(_ name: String) -> String? {
    let foundation: Set = [
        "Date", "URL", "Data", "UUID", "TimeInterval", "CGFloat", "CGPoint", "CGSize", "CGRect",
        "IndexSet"
    ]
    if foundation.contains(name) {
        return "Foundation"
    }
    let simdPrefixes = ["simd_", "float2", "float3", "float4", "matrix_"]
    if simdPrefixes.contains(where: name.hasPrefix) {
        return "simd"
    }
    if name == "CFTimeInterval" || name.hasPrefix("CA") {
        return "QuartzCore"
    }
    return nil
}
