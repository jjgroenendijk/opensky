// Every call to one function name inside a compiled script, so a sweep over the vanilla
// scripts shows who calls a native and with which constant arguments.

import Foundation

nonisolated public struct PexCallSite: Equatable, Sendable {
    public let objectName: String
    public let stateName: String
    public let callerName: String
    public let instructionIndex: Int
    public let opcode: PexOpcode
    public let operands: [PexValue]
}

nonisolated public enum PexCallSites {
    /// Calls of `name`, matched without case, through `callmethod`, `callstatic`, or
    /// `callparent`, in file order.
    public static func find(_ name: String, in file: PexFile) -> [PexCallSite] {
        let wanted = name.lowercased()
        var sites: [PexCallSite] = []
        for object in file.objects {
            for state in object.states {
                for named in state.functions {
                    for (index, instruction) in named.function.instructions.enumerated()
                        where calledName(instruction)?.lowercased() == wanted
                    {
                        sites.append(PexCallSite(
                            objectName: object.name,
                            stateName: state.name,
                            callerName: named.name,
                            instructionIndex: index,
                            opcode: instruction.opcode,
                            operands: instruction.operands
                        ))
                    }
                }
            }
        }
        return sites
    }

    /// One site as `Object "state" Caller#index opcode operands`.
    public static func line(_ site: PexCallSite) -> String {
        "\(site.objectName) \"\(site.stateName)\" \(site.callerName)#\(site.instructionIndex) "
            + "\(site.opcode.name) "
            + site.operands.map(PexDisassembly.text).joined(separator: ", ")
    }

    private static func calledName(_ instruction: PexInstruction) -> String? {
        switch instruction.opcode {
        case .callMethod, .callParent:
            instruction.operands.first?.stringValue
        case .callStatic:
            instruction.operands.count >= 2 ? instruction.operands[1].stringValue : nil
        default:
            nil
        }
    }
}
