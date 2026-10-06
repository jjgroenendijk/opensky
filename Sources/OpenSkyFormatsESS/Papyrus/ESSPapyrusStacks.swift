// Active stack data, function messages, and suspended stacks, read only to count and
// name them: OpenSky's VM cannot resume another VM's stacks. A layout UESP leaves open
// stops the read without failing the table. See docs/formats/ess-papyrus.md#stacks.

import Foundation

nonisolated enum ESSPapyrusStacks {
    static func read(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext, into papyrus: inout ESSPapyrus
    ) -> ESSDecodeStatus {
        do throws(ESSError) {
            for active in papyrus.activeScripts {
                papyrus.activeScriptNames[active.id] = try readActive(&reader, context)
            }
            let messages = try reader.count32("function messages", minimumElementSize: 1)
            for _ in 0 ..< messages {
                guard try reader.uint8("function message") <= 2 else { continue }
                _ = try reader.uint32("function message id")
                _ = try readMessage(&reader, context)
            }
            for list in 1 ... 2 {
                let count = try reader.count32("suspended stacks \(list)", minimumElementSize: 5)
                for _ in 0 ..< count {
                    let id = try reader.uint32("suspended stack id")
                    let name = try readMessage(&reader, context)
                    papyrus.suspendedStacks.append(ESSPapyrusSuspendedStack(
                        id: id,
                        scriptName: name
                    ))
                }
            }
            return .complete
        } catch {
            return .partial(blockedBy: "stack data: \(error)")
        }
    }

    /// A flag byte, then a message naming a script when the flag is set.
    private static func readMessage(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) -> String? {
        guard try reader.uint8("message flag") > 0 else { return nil }
        _ = try reader.uint8("message")
        let script = try context.string(&reader, "message script")
        _ = try context.string(&reader, "message event")
        _ = try context.value(&reader)
        let count = try reader.count32("message variables", minimumElementSize: 5)
        _ = try context.values(&reader, count: count)
        return script
    }

    /// Returns the script of the stack's first frame.
    private static func readActive(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) -> String? {
        _ = try reader.uint32("active script data id")
        try reader.skip(2, "active script version")
        _ = try context.value(&reader)
        let flag = try reader.uint8("active script flag")
        _ = try reader.uint8("active script")
        if flag & 0x01 != 0 {
            _ = try reader.uint32("active script")
        }
        try readOwner(&reader, context)
        let frameCount = try reader.count32("stack frames", minimumElementSize: 20)
        var first: String?
        for _ in 0 ..< frameCount {
            let name = try readFrame(&reader, context)
            first = first ?? name
        }
        if frameCount > 0 {
            _ = try reader.uint8("active script tail")
        }
        return first
    }

    private static func readOwner(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) {
        let kind = try reader.uint8("active script owner")
        guard (1 ... 3).contains(kind) else { return }
        if kind == 2 {
            _ = try context.value(&reader)
            return
        }
        let length = try reader.count32("owner name", minimumElementSize: 1)
        guard let name = try String(bytes: reader.bytes(length, "owner name"), encoding: .utf8)
        else { throw .invalidValue(context: "owner name is not UTF-8") }
        switch name {
        case "TopicInfo": break
        case "QuestStage": try reader.skip(6, "quest stage owner")
        case "ScenePhaseResults", "SceneActionResults": try reader.skip(7, "scene owner")
        case "SceneResults": try reader.skip(3, "scene owner")
        default: throw .invalidValue(context: "active script owner \(name)")
        }
        if kind == 3 {
            _ = try context.value(&reader)
        }
    }

    private static func readFrame(
        _ reader: inout ESSReader, _ context: ESSPapyrusContext
    ) throws(ESSError) -> String {
        let variableCount = try reader.count32("frame variables", minimumElementSize: 5)
        let flag = try reader.uint8("frame flag")
        let functionType = try reader.uint8("frame function type")
        let script = try context.string(&reader, "frame script")
        try reader.skip(4, "frame base name and event")
        if flag & 0x01 == 0, functionType == 0 {
            _ = try reader.uint16("frame status")
        }
        try reader.skip(2 + 2 + 2 + 4 + 1, "frame function header")
        let parameters = try Int(reader.uint16("frame parameters"))
        try reader.skip(parameters * 4, "frame parameters")
        let locals = try Int(reader.uint16("frame locals"))
        try reader.skip(locals * 4, "frame locals")
        let opcodes = try Int(reader.uint16("frame opcodes"))
        for _ in 0 ..< opcodes {
            try skipInstruction(&reader)
        }
        _ = try reader.uint32("frame")
        _ = try context.value(&reader)
        _ = try context.values(&reader, count: variableCount)
        return script
    }

    /// Argument counts per opcode. A call opcode then adds a count and that many more.
    private static let argumentCounts: [Int] = [
        0, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 1, 2, 2, 3, 2, 3, 1, 3,
        3, 3, 2, 2, 3, 3, 4, 4
    ]
    private static let variadicOpcodes: Set<UInt8> = [0x17, 0x18, 0x19]

    private static func skipInstruction(_ reader: inout ESSReader) throws(ESSError) {
        let opcode = try reader.uint8("opcode")
        guard Int(opcode) < argumentCounts.count else {
            throw .invalidValue(context: "opcode \(opcode)")
        }
        for _ in 0 ..< argumentCounts[Int(opcode)] {
            _ = try skipArgument(&reader)
        }
        guard variadicOpcodes.contains(opcode) else { return }
        let extra = try skipArgument(&reader)
        guard extra >= 0, extra <= reader.bytesRemaining else {
            throw .invalidCount(context: "opcode arguments", count: extra)
        }
        for _ in 0 ..< extra {
            _ = try skipArgument(&reader)
        }
    }

    /// Returns the value of an integer argument, which is how a variadic count is stored.
    private static func skipArgument(_ reader: inout ESSReader) throws(ESSError) -> Int {
        let type = try reader.uint8("argument type")
        switch type {
        case 0: return 0
        case 1, 2: try reader.skip(2, "string argument")
        case 3: return try Int(reader.int32("int argument"))
        case 4: try reader.skip(4, "float argument")
        case 5: try reader.skip(1, "bool argument")
        default: throw .invalidValue(context: "argument type \(type)")
        }
        return 0
    }
}
