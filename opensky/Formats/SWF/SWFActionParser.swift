// ACTIONRECORD stream framing (milestone 8.3.1). One byte of `ActionCode`; if
// it is 0x80 or above, a UI16 `Length` and that many operand bytes follow. Code
// 0 is the `ActionEndFlag` and ends the stream. Nothing here executes bytecode.
//
// Malformed bytecode never throws out of `parse(_:)`: a truncated header,
// payload, or nested body size stops that stream and lands in
// `SWFActionBlock.warnings`, because one bad handler must not fail a movie
// (AGENTS.md "Reverse-engineering discipline"). A missing trailing
// `ActionEndFlag` is not an error either — the stream simply ends with the data.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — "DoAction" and "ACTIONRECORD" (p. 63), "DoInitAction" (p. 108).

import Foundation

nonisolated enum SWFActionParser {
    static let doActionCode: UInt16 = 12
    static let doInitActionCode: UInt16 = 59
    /// `ActionEndFlag`: the zero byte that terminates an action stream.
    static let endFlag: UInt8 = 0

    /// Frames an action byte stream. Record offsets are relative to the first
    /// byte of `data`.
    static func parse(_ data: Data) -> SWFActionBlock {
        var framer = Framer(data: data)
        framer.run()
        return framer.block
    }

    /// DoAction (12): the whole tag body is the action stream.
    static func parseDoAction(tag: SWFTag) throws -> SWFActionBlock {
        guard tag.code == doActionCode else {
            throw SWFActionError.unsupportedTag(tag.code)
        }
        return parse(tag.body)
    }

    /// DoInitAction (59): `Sprite ID` UI16 then the action stream. Record
    /// offsets are relative to the stream, not to the tag body, so the sprite
    /// id does not shift them.
    static func parseDoInitAction(tag: SWFTag) throws -> SWFDoInitAction {
        guard tag.code == doInitActionCode else {
            throw SWFActionError.unsupportedTag(tag.code)
        }
        var reader = BinaryReader(tag.body)
        guard
            let spriteId = try? reader.readUInt16(),
            let actionBytes = try? reader.read(count: reader.bytesRemaining)
        else {
            throw SWFActionError.truncatedTag(tag.code)
        }
        return SWFDoInitAction(spriteId: spriteId, actions: parse(actionBytes))
    }
}

/// Sequential ACTIONRECORD framer. Kept as a small mutable value type so the
/// per-record steps stay short enough to read and each failure has exactly one
/// place to record its warning.
private struct Framer {
    let data: Data
    private var reader: BinaryReader
    private var records: [SWFActionRecord] = []
    private var warnings: [SWFActionWarning] = []

    init(data: Data) {
        self.data = data
        reader = BinaryReader(data)
    }

    var block: SWFActionBlock {
        SWFActionBlock(records: records, byteCount: reader.offset, warnings: warnings)
    }

    mutating func run() {
        while reader.bytesRemaining > 0 {
            guard step() else { return }
        }
    }

    /// Frames the record at the cursor. Returns false when the stream must
    /// stop: a clean `ActionEndFlag`, or a framing failure already warned about.
    private mutating func step() -> Bool {
        let offset = reader.offset
        guard let code = try? reader.readUInt8() else {
            warnings.append(.truncatedRecord(offset: offset, code: SWFActionParser.endFlag))
            return false
        }
        if code == SWFActionParser.endFlag {
            return false
        }
        var payload = Data()
        if code >= SWFActionRecord.operandFlag {
            guard
                let length = try? reader.readUInt16(),
                let bytes = try? reader.read(count: Int(length))
            else {
                warnings.append(.truncatedRecord(offset: offset, code: code))
                return false
            }
            payload = bytes
        }
        let record = decoded(code: code, offset: offset, payload: payload)
        records.append(record)
        return nestedBodyFits(record)
    }

    private mutating func decoded(
        code: UInt8,
        offset: Int,
        payload: Data
    ) -> SWFActionRecord {
        var operands = SWFActionOperands.none
        do {
            operands = try SWFActionOperandDecoder
                .decode(code: code, operandBytes: payload) ?? .none
        } catch {
            warnings.append(.malformedOperands(offset: offset, code: code))
        }
        return SWFActionRecord(
            code: code,
            offset: offset,
            endOffset: reader.offset,
            operandBytes: payload,
            operands: operands
        )
    }

    /// A function, With, or Try body is the next N bytes of this same stream.
    /// A size reaching past the end means the following bytes cannot be trusted
    /// as records, so framing stops there instead of inventing opcodes.
    private mutating func nestedBodyFits(_ record: SWFActionRecord) -> Bool {
        let nested: Int
        switch record.operands {
        case let .defineFunction(function):
            nested = function.bodySize
        case let .with(size):
            nested = size
        case let .tryBlock(block):
            nested = block.trySize + block.catchSize + block.finallySize
        default:
            return true
        }
        guard record.endOffset + nested <= data.count else {
            warnings.append(.bodySizeOutOfBounds(offset: record.offset, code: record.code))
            return false
        }
        return true
    }
}
