// ActionScript 1/2 bytecode model: the values an ACTIONRECORD stream decodes
// into. This layer frames and names bytecode and runs nothing (SWF spec v19,
// ch. 5, pp. 63-118; docs/formats/swf-actions.md).

import Foundation

nonisolated public enum SWFActionError: Error, Equatable, Sendable {
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
nonisolated public struct SWFDefineFunctionFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let preloadParent = SWFDefineFunctionFlags(rawValue: 0x8000)
    public static let preloadRoot = SWFDefineFunctionFlags(rawValue: 0x4000)
    public static let preloadSuper = SWFDefineFunctionFlags(rawValue: 0x1000)
    public static let suppressArguments = SWFDefineFunctionFlags(rawValue: 0x0800)
    public static let preloadArguments = SWFDefineFunctionFlags(rawValue: 0x0400)
    public static let preloadThis = SWFDefineFunctionFlags(rawValue: 0x0100)
    public static let preloadGlobal = SWFDefineFunctionFlags(rawValue: 0x0001)
}

/// Why an action stream stopped early or lost detail. Recorded, never thrown:
/// malformed bytecode must not fail a movie (AGENTS.md "Reverse-engineering
/// discipline"), so the records framed before the problem stay usable.
nonisolated public enum SWFActionWarning: Equatable, Sendable {
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
nonisolated public enum SWFActionValue: Equatable, Sendable {
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
nonisolated public struct SWFGetURL2Flags: Equatable, Sendable {
    /// `SendVarsMethod`: 0 = none, 1 = HTTP GET, 2 = HTTP POST.
    public let sendVarsMethod: UInt8
    /// `LoadTargetFlag`: false = browser window, true = path to a sprite.
    public let loadTarget: Bool
    /// `LoadVariablesFlag`.
    public let loadVariables: Bool
}

/// `ActionDefineFunction` (spec p. 92) and `ActionDefineFunction2` (p. 111)
/// header. The function body is not nested inside the record: the next
/// `bodySize` bytes of the same stream are the body, so an interpreter reads it
/// with `SWFActionBlock.records(from:byteCount:)` starting at the record's
/// `endOffset`.
nonisolated public struct SWFActionFunction: Equatable, Sendable {
    /// `FunctionName`; empty for an anonymous function literal.
    public let name: String
    /// Parameter names in declaration order.
    public let parameterNames: [String]
    /// `ActionDefineFunction2` REGISTERPARAM `Register` per parameter, in the
    /// same order as `parameterNames` (0 means "bind as a named variable").
    /// Empty for `ActionDefineFunction`, which has no register parameters.
    public let parameterRegisters: [UInt8]
    /// `ActionDefineFunction2` `RegisterCount`; 0 for `ActionDefineFunction`.
    public let registerCount: UInt8
    /// `ActionDefineFunction2` preload/suppress flags; empty for
    /// `ActionDefineFunction`, which has none.
    public let flags: SWFDefineFunctionFlags
    /// `codeSize`: how many bytes of the stream after this record form the body.
    public let bodySize: Int
}

/// `ActionTry` header (spec "ActionTry", p. 115). Like a function body, the
/// try/catch/finally bodies are the following bytes of the same stream, sized
/// by `trySize`, `catchSize`, and `finallySize` in that order.
nonisolated public struct SWFActionTryBlock: Equatable, Sendable {
    /// `CatchInRegisterFlag`.
    public let catchInRegister: Bool
    /// `FinallyBlockFlag`.
    public let hasFinallyBlock: Bool
    /// `CatchBlockFlag`.
    public let hasCatchBlock: Bool
    public let trySize: Int
    public let catchSize: Int
    public let finallySize: Int
    /// `CatchName`, present when `catchInRegister` is false; otherwise empty.
    public let catchName: String
    /// `CatchRegister`, present when `catchInRegister` is true; otherwise nil.
    public let catchRegister: UInt8?
}

/// Typed operands for the records this stage decodes. Every other record is
/// still framed correctly and keeps its bytes in
/// `SWFActionRecord.operandBytes`, reporting `.none` here — nothing is dropped.
nonisolated public enum SWFActionOperands: Equatable, Sendable {
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
nonisolated public struct SWFActionRecord: Equatable, Sendable {
    /// ACTIONRECORDHEADER `ActionCode`.
    public let code: UInt8
    /// Byte offset of this record's `ActionCode` within its block. Branch
    /// targets and function bodies address records by this value.
    public let offset: Int
    /// Byte offset one past this record. `ActionJump`/`ActionIf` add their
    /// `BranchOffset` to this, and a function/With/Try body starts here.
    public let endOffset: Int
    /// The operand payload verbatim; empty when `code` is below 0x80, which the
    /// spec defines as carrying no payload.
    public let operandBytes: Data
    /// Typed decode of `operandBytes`, `.none` when this stage frames the
    /// opcode without interpreting it.
    public let operands: SWFActionOperands

    /// Adobe name of the opcode, or nil when the code is not in the spec.
    public var name: String? {
        SWFActionName.name(forCode: code)
    }

    /// Whether the ACTIONRECORDHEADER carries a `Length` field and a payload.
    public var carriesOperands: Bool {
        code >= SWFActionRecord.operandFlag
    }

    /// An `ActionCode` at or above this value is followed by a UI16 `Length`.
    public static let operandFlag: UInt8 = 0x80
}

/// A parsed ACTIONRECORD stream — one DoAction/DoInitAction tag body, or one
/// CLIPACTIONRECORD's actions. Records are in stream order and their offsets
/// ascend, so a byte offset resolves by binary search rather than an index that
/// would have to be kept in sync.
nonisolated public struct SWFActionBlock: Equatable, Sendable {
    /// Records in stream order. The terminating `ActionEndFlag` is consumed,
    /// not stored.
    public let records: [SWFActionRecord]
    /// Bytes consumed from the source data, including the trailing
    /// `ActionEndFlag` byte when the stream had one.
    public let byteCount: Int
    /// Framing problems recorded instead of thrown. Non-empty means the stream
    /// stopped early or a record lost its typed operands.
    public let warnings: [SWFActionWarning]

    /// Index into `records` of the record that starts exactly at `offset`, or
    /// nil when nothing starts there — a branch into the middle of a record,
    /// which an interpreter must treat as a failed jump rather than a crash.
    public func index(atOffset offset: Int) -> Int? {
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
    public func record(atOffset offset: Int) -> SWFActionRecord? {
        index(atOffset: offset).map { records[$0] }
    }

    /// The records fully inside `[offset, offset + byteCount)` — the body of an
    /// `ActionDefineFunction`, `ActionWith`, or `ActionTry` block. Empty when
    /// `offset` does not start a record.
    public func records(from offset: Int, byteCount: Int) -> ArraySlice<SWFActionRecord> {
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
nonisolated public struct SWFDoInitAction: Equatable, Sendable {
    public let spriteId: UInt16
    public let actions: SWFActionBlock
}
