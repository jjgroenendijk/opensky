// A compiled script as text: its objects, variables, properties, states, and each
// function's instructions with resolved names. Opcode names follow the UESP page
// "Skyrim Mod:Compiled Script File Format" (docs/formats/pex.md).

import Foundation

nonisolated public enum PexDisassembly {
    /// Every line of `file`. A non-empty `function` keeps only the functions of that
    /// name, matched without case, and the object lines above them.
    public static func lines(of file: PexFile, function: String = "") -> [String] {
        let wanted = function.lowercased()
        var lines = [
            "script \(file.header.sourceFileName) (PEX \(file.header.majorVersion)."
                + "\(file.header.minorVersion), \(file.strings.count) strings)"
        ]
        for object in file.objects {
            let parent = object.parentClassName.isEmpty ? "" : " extends \(object.parentClassName)"
            lines.append("object \(object.name)\(parent)")
            if wanted.isEmpty {
                lines += object.variables.map {
                    "  variable \($0.typeName) \($0.name) = \(text($0.initialValue))"
                }
                lines += object.properties.map(propertyLine)
            }
            for state in object.states {
                let functions = state.functions.filter {
                    wanted.isEmpty || $0.name.lowercased() == wanted
                }
                guard !functions.isEmpty else { continue }
                lines.append("  state \"\(state.name)\"")
                for named in functions {
                    lines += functionLines(named.name, named.function)
                }
            }
        }
        return lines
    }

    public static func text(_ value: PexValue) -> String {
        switch value {
        case .null: "none"
        case let .identifier(name): name
        case let .string(string): "\"\(string)\""
        case let .integer(number): String(number)
        case let .float(number): String(number)
        case let .boolean(flag): String(flag)
        }
    }

    private static func propertyLine(_ property: PexProperty) -> String {
        let backing = property.automaticVariableName.map { " auto(\($0))" } ?? ""
        return "  property \(property.typeName) \(property.name)\(backing)"
    }

    private static func functionLines(_ name: String, _ function: PexFunction) -> [String] {
        let parameters = function.parameters.map { "\($0.typeName) \($0.name)" }
        var flags = ""
        if function.flags.contains(.global) {
            flags += " global"
        }
        if function.flags.contains(.native) {
            flags += " native"
        }
        var lines = [
            "    function \(function.returnTypeName) \(name)("
                + parameters.joined(separator: ", ") + ")\(flags)"
        ]
        lines += function.localVariables.map { "      local \($0.typeName) \($0.name)" }
        for (index, instruction) in function.instructions.enumerated() {
            let words = [String(index), instruction.opcode.name]
                + (instruction.operands.isEmpty
                    ? [] : [instruction.operands.map(text).joined(separator: ", ")])
            lines.append("      " + words.joined(separator: " "))
        }
        return lines
    }
}
