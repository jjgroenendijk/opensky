// Typed operand decoding for the ACTIONRECORDs milestone 8.3.1 inventories.
// Opcodes outside `decodableCodes` are still framed and keep their operand
// bytes verbatim (see `SWFActionParser`); nothing is dropped, and a malformed
// payload degrades to a recorded warning rather than a thrown movie failure.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — the per-action field tables in the SWF 3 action model (pp. 64-66),
// SWF 4 action model (pp. 68-88), SWF 5 action model (pp. 89-107), and SWF 7
// action model (pp. 111-116).

import Foundation

nonisolated enum SWFActionOperandDecoder {
    /// Opcodes with a typed decode below. Everything else frames to
    /// `SWFActionOperands.none` with its bytes retained.
    static let decodableCodes: Set<UInt8> = [
        0x81, 0x83, 0x87, 0x88, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F,
        0x94, 0x96, 0x99, 0x9A, 0x9B, 0x9D, 0x9F
    ]

    /// Decodes one record's operand payload, or nil when the opcode has no
    /// typed decode at this stage. Throws when the payload is malformed.
    static func decode(code: UInt8, operandBytes: Data) throws -> SWFActionOperands? {
        guard decodableCodes.contains(code) else {
            return nil
        }
        var reader = BinaryReader(operandBytes)
        if let operands = try decodeTargeting(code: code, from: &reader) {
            return operands
        }
        if let operands = try decodeStack(code: code, from: &reader) {
            return operands
        }
        return try decodeFlow(code: code, from: &reader)
    }

    /// SWF 3 actions addressing a frame, URL, or target by name.
    private static func decodeTargeting(
        code: UInt8,
        from reader: inout BinaryReader
    ) throws -> SWFActionOperands? {
        switch code {
        case 0x81: // ActionGotoFrame: Frame UI16
            return try .gotoFrame(reader.readUInt16())
        case 0x83: // ActionGetURL: UrlString STRING, TargetString STRING
            let url = try readString(&reader)
            return try .getURL(url: url, target: readString(&reader))
        case 0x8A: // ActionWaitForFrame: Frame UI16, SkipCount UI8
            let frame = try reader.readUInt16()
            return try .waitForFrame(frame: frame, skipCount: reader.readUInt8())
        case 0x8B: // ActionSetTarget: TargetName STRING
            return try .setTarget(readString(&reader))
        case 0x8C: // ActionGoToLabel: Label STRING
            return try .goToLabel(readString(&reader))
        default:
            return nil
        }
    }

    /// Actions carrying stack values, registers, or the constant pool.
    private static func decodeStack(
        code: UInt8,
        from reader: inout BinaryReader
    ) throws -> SWFActionOperands? {
        switch code {
        case 0x87: // ActionStoreRegister: RegisterNumber UI8
            return try .storeRegister(reader.readUInt8())
        case 0x88: // ActionConstantPool: Count UI16, ConstantPool STRING[Count]
            let count = try Int(reader.readUInt16())
            var pool: [String] = []
            pool.reserveCapacity(min(count, reader.bytesRemaining))
            for _ in 0 ..< count {
                try pool.append(readString(&reader))
            }
            return .constantPool(pool)
        case 0x96: // ActionPush: repeated Type + value until the payload ends
            var values: [SWFActionValue] = []
            while reader.bytesRemaining > 0 {
                try values.append(readPushValue(&reader))
            }
            return .push(values)
        default:
            return nil
        }
    }

    /// Branching, block-scoping, and function-defining actions.
    private static func decodeFlow(
        code: UInt8,
        from reader: inout BinaryReader
    ) throws -> SWFActionOperands? {
        switch code {
        case 0x99, 0x9D: // ActionJump / ActionIf: BranchOffset SI16
            return try .branch(offset: Int16(bitPattern: reader.readUInt16()))
        case 0x94: // ActionWith: Size UI16
            return try .with(bodySize: Int(reader.readUInt16()))
        case 0x8D: // ActionWaitForFrame2: SkipCount UI8
            return try .waitForFrame2(skipCount: reader.readUInt8())
        case 0x9A: // ActionGetURL2: one packed flag byte
            return try .getURL2(readGetURL2Flags(&reader))
        case 0x9F: // ActionGotoFrame2: flag byte then optional SceneBias UI16
            let flags = try reader.readUInt8()
            let bias = try flags & 0x02 != 0 ? reader.readUInt16() : 0
            return .gotoFrame2(play: flags & 0x01 != 0, sceneBias: bias)
        case 0x8E, 0x9B: // ActionDefineFunction2 / ActionDefineFunction
            return try .defineFunction(readFunction(&reader, isVersion2: code == 0x8E))
        case 0x8F: // ActionTry
            return try .tryBlock(readTryBlock(&reader))
        default:
            return nil
        }
    }
}

// MARK: - Field readers

extension SWFActionOperandDecoder {
    /// One `ActionPush` `Type` byte and the value it selects (spec p. 69).
    private static func readPushValue(_ reader: inout BinaryReader) throws -> SWFActionValue {
        let type = try reader.readUInt8()
        switch type {
        case 0: return try .string(readString(&reader))
        case 1: return try .float(reader.readFloat32())
        case 2: return .null
        case 3: return .undefined
        case 4: return try .register(reader.readUInt8())
        case 5: return try .boolean(reader.readUInt8() != 0)
        case 6: return try .double(readDouble(&reader))
        case 7: return try .integer(Int32(bitPattern: reader.readUInt32()))
        case 8: return try .constant8(reader.readUInt8())
        case 9: return try .constant16(reader.readUInt16())
        default: throw SWFActionError.unknownPushType(type)
        }
    }

    /// `ActionPush` type 6. The specification calls this a little-endian
    /// DOUBLE, but Flash authoring tools write the two 32-bit halves with the
    /// high-order word first, so the value is reassembled from two UI32 reads
    /// rather than one UI64. Confirmed against the vanilla Interface movies:
    /// reading it as a plain little-endian UI64 turns ordinary small constants
    /// into denormals.
    private static func readDouble(_ reader: inout BinaryReader) throws -> Double {
        let high = try reader.readUInt32()
        let low = try reader.readUInt32()
        return Double(bitPattern: UInt64(high) << 32 | UInt64(low))
    }

    /// `ActionGetURL2`, MSB to LSB: `SendVarsMethod` UB[2], reserved UB[4],
    /// `LoadTargetFlag` UB[1], `LoadVariablesFlag` UB[1].
    private static func readGetURL2Flags(
        _ reader: inout BinaryReader
    ) throws -> SWFGetURL2Flags {
        let flags = try reader.readUInt8()
        return SWFGetURL2Flags(
            sendVarsMethod: (flags >> 6) & 0x03,
            loadTarget: flags & 0x02 != 0,
            loadVariables: flags & 0x01 != 0
        )
    }

    /// `ActionDefineFunction` (p. 92) and `ActionDefineFunction2` (p. 111).
    /// Version 2 inserts `RegisterCount` and the flag word before the
    /// parameters and gives every parameter a register number.
    private static func readFunction(
        _ reader: inout BinaryReader,
        isVersion2: Bool
    ) throws -> SWFActionFunction {
        let name = try readString(&reader)
        let parameterCount = try Int(reader.readUInt16())
        var registerCount: UInt8 = 0
        var flags = SWFDefineFunctionFlags(rawValue: 0)
        if isVersion2 {
            registerCount = try reader.readUInt8()
            let high = try reader.readUInt8()
            let low = try reader.readUInt8()
            flags = SWFDefineFunctionFlags(rawValue: UInt16(high) << 8 | UInt16(low))
        }
        var names: [String] = []
        var registers: [UInt8] = []
        for _ in 0 ..< parameterCount {
            if isVersion2 {
                try registers.append(reader.readUInt8())
            }
            try names.append(readString(&reader))
        }
        return try SWFActionFunction(
            name: name,
            parameterNames: names,
            parameterRegisters: registers,
            registerCount: registerCount,
            flags: flags,
            bodySize: Int(reader.readUInt16())
        )
    }

    /// `ActionTry` (p. 115). The first byte is reserved UB[5],
    /// `CatchInRegisterFlag` UB[1], `FinallyBlockFlag` UB[1], `CatchBlockFlag`
    /// UB[1]; the three sizes always follow, whether or not their flags are set.
    private static func readTryBlock(
        _ reader: inout BinaryReader
    ) throws -> SWFActionTryBlock {
        let flags = try reader.readUInt8()
        let catchInRegister = flags & 0x04 != 0
        let trySize = try Int(reader.readUInt16())
        let catchSize = try Int(reader.readUInt16())
        let finallySize = try Int(reader.readUInt16())
        let name = try catchInRegister ? "" : readString(&reader)
        let register = try catchInRegister ? reader.readUInt8() : nil
        return SWFActionTryBlock(
            catchInRegister: catchInRegister,
            hasFinallyBlock: flags & 0x02 != 0,
            hasCatchBlock: flags & 0x01 != 0,
            trySize: trySize,
            catchSize: catchSize,
            finallySize: finallySize,
            catchName: name,
            catchRegister: register
        )
    }

    /// Null-terminated STRING, UTF-8 with a CP1252 fallback — the same
    /// convention `SWFEditText` and `SWFDisplayListParser` use, since SWF 6 and
    /// later declare strings UTF-8 while older movies are code-page bytes.
    private static func readString(_ reader: inout BinaryReader) throws -> String {
        let bytes = try reader.readZStringData()
        return String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .windowsCP1252) ?? ""
    }
}
