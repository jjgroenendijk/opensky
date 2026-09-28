// ActionScript 1/2 bytecode model (milestone 8.3.1): the value types a parsed
// ACTIONRECORD stream decodes into. This layer frames and names bytecode; it
// executes nothing. A later interpreter walks `SWFActionBlock.records` in order
// and resolves branch targets through `SWFActionBlock.record(atOffset:)`.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "ACTIONRECORD" (p. 63) for the record framing and the per-action
// field tables in the SWF 3 through SWF 7 action-model sections (pp. 63-118).

import Foundation

nonisolated enum SWFActionError: Error, Equatable {
    /// Tag code handed to a parser expecting DoAction (12) or DoInitAction (59).
    case unsupportedTag(UInt16)
    /// DoInitAction body too short to hold its `Sprite ID`.
    case truncatedTag(UInt16)
    /// `ActionPush` named a `Type` byte the specification does not define, so
    /// the rest of the payload cannot be framed.
    case unknownPushType(UInt8)
}

/// `ActionDefineFunction2` preload/suppress flags (spec p. 111). The two flag
/// bytes are read big-endian so the bit values match the order the spec's field
/// table lists them in.
nonisolated struct SWFDefineFunctionFlags: OptionSet, Equatable {
    let rawValue: UInt16

    static let preloadParent = SWFDefineFunctionFlags(rawValue: 0x8000)
    static let preloadRoot = SWFDefineFunctionFlags(rawValue: 0x4000)
    static let suppressSuper = SWFDefineFunctionFlags(rawValue: 0x2000)
    static let preloadSuper = SWFDefineFunctionFlags(rawValue: 0x1000)
    static let suppressArguments = SWFDefineFunctionFlags(rawValue: 0x0800)
    static let preloadArguments = SWFDefineFunctionFlags(rawValue: 0x0400)
    static let suppressThis = SWFDefineFunctionFlags(rawValue: 0x0200)
    static let preloadThis = SWFDefineFunctionFlags(rawValue: 0x0100)
    static let preloadGlobal = SWFDefineFunctionFlags(rawValue: 0x0001)
}

/// Why an action stream stopped early or lost detail. Recorded, never thrown:
/// malformed bytecode must not fail a movie (AGENTS.md "Reverse-engineering
/// discipline"), so the records framed before the problem stay usable.
nonisolated enum SWFActionWarning: Equatable {
    /// A record header or its operand payload ran past the end of the stream.
    /// Framing stops here; earlier records are kept.
    case truncatedRecord(offset: Int, code: UInt8)
    /// Typed operand decode failed. The record keeps its raw operand bytes and
    /// reports `.none` operands; framing continues at the next record.
    case malformedOperands(offset: Int, code: UInt8)
    /// A nested body size (`ActionDefineFunction`/`ActionDefineFunction2`
    /// `codeSize`, `ActionWith` `Size`, or the `ActionTry` block sizes) reached
    /// past the end of the stream. Framing stops here.
    case bodySizeOutOfBounds(offset: Int, code: UInt8)
    /// A CLIPACTIONS block could not be framed at this byte offset in the
    /// PlaceObject2/PlaceObject3 body. Handlers after it are not recovered.
    case malformedClipActions(offset: Int)
}

/// One value pushed by `ActionPush` (spec "ActionPush", p. 69). The `Type` byte
/// selects the case; types 2 through 9 exist from SWF 5 on.
nonisolated enum SWFActionValue: Equatable {
    /// Type 0: null-terminated STRING.
    case string(String)
    /// Type 1: 32-bit IEEE single-precision little-endian FLOAT.
    case float(Float)
    /// Type 2.
    case null
    /// Type 3.
    case undefined
    /// Type 4: register number.
    case register(UInt8)
    /// Type 5: Boolean (a non-zero byte is true).
    case boolean(Bool)
    /// Type 6: 64-bit IEEE double-precision DOUBLE.
    case double(Double)
    /// Type 7: 32-bit little-endian integer, read as signed because that is the
    /// ActionScript numeric domain.
    case integer(Int32)
    /// Type 8: constant-pool index below 256.
    case constant8(UInt8)
    /// Type 9: constant-pool index of 256 or more.
    case constant16(UInt16)
}

/// `ActionGetURL2` flag byte (spec "ActionGetURL2", p. 82).
nonisolated struct SWFGetURL2Flags: Equatable {
    /// `SendVarsMethod`: 0 = none, 1 = HTTP GET, 2 = HTTP POST.
    let sendVarsMethod: UInt8
    /// `LoadTargetFlag`: false = browser window, true = path to a sprite.
    let loadTarget: Bool
    /// `LoadVariablesFlag`.
    let loadVariables: Bool
}

/// `ActionDefineFunction` (spec p. 92) and `ActionDefineFunction2` (p. 111)
/// header. The function body is not nested inside the record: the next
/// `bodySize` bytes of the same stream are the body, so an interpreter reads it
/// with `SWFActionBlock.records(from:byteCount:)` starting at the record's
/// `endOffset`.
nonisolated struct SWFActionFunction: Equatable {
    /// `FunctionName`; empty for an anonymous function literal.
    let name: String
    /// Parameter names in declaration order.
    let parameterNames: [String]
    /// `ActionDefineFunction2` REGISTERPARAM `Register` per parameter, in the
    /// same order as `parameterNames` (0 means "bind as a named variable").
    /// Empty for `ActionDefineFunction`, which has no register parameters.
    let parameterRegisters: [UInt8]
    /// `ActionDefineFunction2` `RegisterCount`; 0 for `ActionDefineFunction`.
    let registerCount: UInt8
    /// `ActionDefineFunction2` preload/suppress flags; empty for
    /// `ActionDefineFunction`, which has none.
    let flags: SWFDefineFunctionFlags
    /// `codeSize`: how many bytes of the stream after this record form the body.
    let bodySize: Int
}

/// `ActionTry` header (spec "ActionTry", p. 115). Like a function body, the
/// try/catch/finally bodies are the following bytes of the same stream, sized
/// by `trySize`, `catchSize`, and `finallySize` in that order.
nonisolated struct SWFActionTryBlock: Equatable {
    /// `CatchInRegisterFlag`.
    let catchInRegister: Bool
    /// `FinallyBlockFlag`.
    let hasFinallyBlock: Bool
    /// `CatchBlockFlag`.
    let hasCatchBlock: Bool
    let trySize: Int
    let catchSize: Int
    let finallySize: Int
    /// `CatchName`, present when `catchInRegister` is false; otherwise empty.
    let catchName: String
    /// `CatchRegister`, present when `catchInRegister` is true; otherwise nil.
    let catchRegister: UInt8?
}

/// Typed operands for the records this stage decodes. Every other record is
/// still framed correctly and keeps its bytes in
/// `SWFActionRecord.operandBytes`, reporting `.none` here — nothing is dropped.
nonisolated enum SWFActionOperands: Equatable {
    /// No operands, or operands this stage does not decode further.
    case none
    /// `ActionPush` (0x96): one or more typed values, in push order.
    case push([SWFActionValue])
    /// `ActionConstantPool` (0x88): the replacement constant pool.
    case constantPool([String])
    /// `ActionJump` (0x99) / `ActionIf` (0x9D): `BranchOffset`, a byte delta
    /// relative to the record's `endOffset`.
    case branch(offset: Int16)
    /// `ActionGotoFrame` (0x81): zero-based `Frame` index.
    case gotoFrame(UInt16)
    /// `ActionGotoFrame2` (0x9F): `Play flag` and the optional `SceneBias`.
    case gotoFrame2(play: Bool, sceneBias: UInt16)
    /// `ActionWaitForFrame` (0x8A): `Frame` and `SkipCount`.
    case waitForFrame(frame: UInt16, skipCount: UInt8)
    /// `ActionWaitForFrame2` (0x8D): `SkipCount`.
    case waitForFrame2(skipCount: UInt8)
    /// `ActionGetURL` (0x83): `UrlString` and `TargetString`.
    case getURL(url: String, target: String)
    /// `ActionGetURL2` (0x9A).
    case getURL2(SWFGetURL2Flags)
    /// `ActionGoToLabel` (0x8C): `Label`.
    case goToLabel(String)
    /// `ActionSetTarget` (0x8B): `TargetName`.
    case setTarget(String)
    /// `ActionStoreRegister` (0x87): `RegisterNumber`.
    case storeRegister(UInt8)
    /// `ActionWith` (0x94): `Size`, the byte length of the With body that
    /// follows this record.
    case with(bodySize: Int)
    /// `ActionDefineFunction` (0x9B) or `ActionDefineFunction2` (0x8E); the
    /// record's `code` says which.
    case defineFunction(SWFActionFunction)
    /// `ActionTry` (0x8F).
    case tryBlock(SWFActionTryBlock)
}

/// One ACTIONRECORD: its opcode, where it sits in its stream, its raw operand
/// bytes, and the typed decode when this stage understands the opcode.
nonisolated struct SWFActionRecord: Equatable {
    /// ACTIONRECORDHEADER `ActionCode`.
    let code: UInt8
    /// Byte offset of this record's `ActionCode` within its block. Branch
    /// targets and function bodies address records by this value.
    let offset: Int
    /// Byte offset one past this record. `ActionJump`/`ActionIf` add their
    /// `BranchOffset` to this, and a function/With/Try body starts here.
    let endOffset: Int
    /// The operand payload verbatim; empty when `code` is below 0x80, which the
    /// spec defines as carrying no payload.
    let operandBytes: Data
    /// Typed decode of `operandBytes`, `.none` when this stage frames the
    /// opcode without interpreting it.
    let operands: SWFActionOperands

    /// Adobe name of the opcode, or nil when the code is not in the spec.
    var name: String? {
        SWFActionName.name(forCode: code)
    }

    /// Whether the ACTIONRECORDHEADER carries a `Length` field and a payload.
    var carriesOperands: Bool {
        code >= SWFActionRecord.operandFlag
    }

    /// An `ActionCode` at or above this value is followed by a UI16 `Length`.
    static let operandFlag: UInt8 = 0x80
}

/// A parsed ACTIONRECORD stream — one DoAction/DoInitAction tag body, or one
/// CLIPACTIONRECORD's actions. Records are in stream order and their offsets
/// ascend, so a byte offset resolves by binary search rather than an index that
/// would have to be kept in sync.
nonisolated struct SWFActionBlock: Equatable {
    /// Records in stream order. The terminating `ActionEndFlag` is consumed,
    /// not stored.
    let records: [SWFActionRecord]
    /// Bytes consumed from the source data, including the trailing
    /// `ActionEndFlag` byte when the stream had one.
    let byteCount: Int
    /// Framing problems recorded instead of thrown. Non-empty means the stream
    /// stopped early or a record lost its typed operands.
    let warnings: [SWFActionWarning]

    static let empty = SWFActionBlock(records: [], byteCount: 0, warnings: [])

    /// Index into `records` of the record that starts exactly at `offset`, or
    /// nil when nothing starts there — a branch into the middle of a record,
    /// which an interpreter must treat as a failed jump rather than a crash.
    func index(atOffset offset: Int) -> Int? {
        var low = records.startIndex
        var high = records.endIndex
        while low < high {
            let middle = low + (high - low) / 2
            let candidate = records[middle].offset
            if candidate == offset {
                return middle
            }
            if candidate < offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return nil
    }

    /// The record starting exactly at `offset`, or nil.
    func record(atOffset offset: Int) -> SWFActionRecord? {
        index(atOffset: offset).map { records[$0] }
    }

    /// The records fully inside `[offset, offset + byteCount)` — the body of an
    /// `ActionDefineFunction`, `ActionWith`, or `ActionTry` block. Empty when
    /// `offset` does not start a record.
    func records(from offset: Int, byteCount: Int) -> ArraySlice<SWFActionRecord> {
        guard let start = index(atOffset: offset) else {
            return []
        }
        let limit = offset + byteCount
        var end = start
        while end < records.endIndex, records[end].endOffset <= limit {
            end += 1
        }
        return records[start ..< end]
    }
}

/// A DoInitAction (59) tag: the sprite whose first instantiation the actions
/// precede, plus the actions themselves.
nonisolated struct SWFDoInitAction: Equatable {
    let spriteId: UInt16
    let actions: SWFActionBlock
}
