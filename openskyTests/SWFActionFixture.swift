// Synthetic ACTIONRECORD stream builders (milestone 8.3.1): opcode framing,
// every ActionPush value type, the block-shaped actions, and the CLIPACTIONS
// wrapper — assembled byte by byte following the Adobe SWF File Format
// Specification v19 chapters 3 and 5, never extracted game files (AGENTS.md
// "Legal & IP boundary").

import Foundation
@testable import opensky

enum SWFActionFixture {
    /// One record to emit: an opcode plus the operand bytes it carries.
    /// Opcodes below 0x80 emit no length and no payload.
    struct Action {
        let code: UInt8
        var operands = Data()
    }

    /// A value for `ActionPush`, mirroring `SWFActionValue` on the write side.
    enum PushValue {
        case string(String)
        case float(Float)
        case null
        case undefined
        case register(UInt8)
        case boolean(Bool)
        case double(Double)
        case integer(Int32)
        case constant8(UInt8)
        case constant16(UInt16)
    }

    /// One CLIPACTIONRECORD.
    struct ClipHandler {
        var events: SWFClipEventFlags
        var keyCode: UInt8?
        /// An already-framed action stream (see `stream(_:appendEnd:)`).
        var actions: Data
    }

    /// ACTIONRECORD framing: `ActionCode` UI8, and for codes 0x80 and above a
    /// UI16 `Length` plus that many operand bytes. `appendEnd` writes the
    /// terminating `ActionEndFlag`.
    static func stream(_ actions: [Action], appendEnd: Bool = true) -> Data {
        var data = Data()
        for action in actions {
            data.append(action.code)
            if action.code >= 0x80 {
                var writer = SWFBitWriter()
                writer.appendUInt16LE(UInt16(action.operands.count))
                data.append(writer.bytes())
                data.append(action.operands)
            }
        }
        if appendEnd {
            data.append(0)
        }
        return data
    }
}

// MARK: - Record builders

extension SWFActionFixture {
    static func noOperands(_ code: UInt8) -> Action {
        Action(code: code)
    }

    static func push(_ values: [PushValue]) -> Action {
        var operands = Data()
        for value in values {
            operands.append(encode(value))
        }
        return Action(code: 0x96, operands: operands)
    }

    static func constantPool(_ strings: [String]) -> Action {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(UInt16(strings.count))
        for string in strings {
            writer.appendBytes(Array(string.utf8))
            writer.appendByte(0)
        }
        return Action(code: 0x88, operands: writer.bytes())
    }

    /// `ActionJump` (0x99) or `ActionIf` (0x9D): SI16 `BranchOffset`.
    static func branch(code: UInt8, offset: Int16) -> Action {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(UInt16(bitPattern: offset))
        return Action(code: code, operands: writer.bytes())
    }

    static func gotoFrame(_ frame: UInt16) -> Action {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(frame)
        return Action(code: 0x81, operands: writer.bytes())
    }

    static func gotoFrame2(play: Bool, sceneBias: UInt16?) -> Action {
        var writer = SWFBitWriter()
        writer.appendByte((sceneBias != nil ? 0x02 : 0) | (play ? 0x01 : 0))
        if let sceneBias {
            writer.appendUInt16LE(sceneBias)
        }
        return Action(code: 0x9F, operands: writer.bytes())
    }

    static func waitForFrame(frame: UInt16, skipCount: UInt8) -> Action {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(frame)
        writer.appendByte(skipCount)
        return Action(code: 0x8A, operands: writer.bytes())
    }

    static func waitForFrame2(skipCount: UInt8) -> Action {
        Action(code: 0x8D, operands: Data([skipCount]))
    }

    static func getURL(url: String, target: String) -> Action {
        var writer = SWFBitWriter()
        appendString(&writer, url)
        appendString(&writer, target)
        return Action(code: 0x83, operands: writer.bytes())
    }

    static func getURL2(sendVarsMethod: UInt8, loadTarget: Bool, loadVariables: Bool) -> Action {
        let flags = (sendVarsMethod << 6) | (loadTarget ? 0x02 : 0) | (loadVariables ? 0x01 : 0)
        return Action(code: 0x9A, operands: Data([flags]))
    }

    static func storeRegister(_ number: UInt8) -> Action {
        Action(code: 0x87, operands: Data([number]))
    }

    static func setTarget(_ name: String) -> Action {
        var writer = SWFBitWriter()
        appendString(&writer, name)
        return Action(code: 0x8B, operands: writer.bytes())
    }

    static func goToLabel(_ label: String) -> Action {
        var writer = SWFBitWriter()
        appendString(&writer, label)
        return Action(code: 0x8C, operands: writer.bytes())
    }

    static func with(bodySize: UInt16) -> Action {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(bodySize)
        return Action(code: 0x94, operands: writer.bytes())
    }

    /// `ActionDefineFunction` (0x9B): name, parameter names, `codeSize`.
    static func defineFunction(
        name: String,
        parameters: [String],
        bodySize: UInt16
    ) -> Action {
        var writer = SWFBitWriter()
        appendString(&writer, name)
        writer.appendUInt16LE(UInt16(parameters.count))
        for parameter in parameters {
            appendString(&writer, parameter)
        }
        writer.appendUInt16LE(bodySize)
        return Action(code: 0x9B, operands: writer.bytes())
    }

    /// `ActionDefineFunction2` (0x8E). `parameters` pairs each register number
    /// with its parameter name in REGISTERPARAM order.
    static func defineFunction2(
        name: String,
        parameters: [(UInt8, String)],
        registerCount: UInt8,
        flags: SWFDefineFunctionFlags,
        bodySize: UInt16
    ) -> Action {
        var writer = SWFBitWriter()
        appendString(&writer, name)
        writer.appendUInt16LE(UInt16(parameters.count))
        writer.appendByte(registerCount)
        writer.appendByte(UInt8(flags.rawValue >> 8))
        writer.appendByte(UInt8(flags.rawValue & 0xFF))
        for (register, parameterName) in parameters {
            writer.appendByte(register)
            appendString(&writer, parameterName)
        }
        writer.appendUInt16LE(bodySize)
        return Action(code: 0x8E, operands: writer.bytes())
    }

    /// `ActionTry` (0x8F) with a named catch variable.
    static func tryBlock(
        catchName: String,
        trySize: UInt16,
        catchSize: UInt16,
        finallySize: UInt16
    ) -> Action {
        var writer = SWFBitWriter()
        writer.appendByte((finallySize > 0 ? 0x02 : 0) | (catchSize > 0 ? 0x01 : 0))
        writer.appendUInt16LE(trySize)
        writer.appendUInt16LE(catchSize)
        writer.appendUInt16LE(finallySize)
        appendString(&writer, catchName)
        return Action(code: 0x8F, operands: writer.bytes())
    }
}

// MARK: - Tag and CLIPACTIONS wrappers

extension SWFActionFixture {
    /// DoAction (12).
    static func doActionTag(_ actions: [Action]) -> SWFFixture.Tag {
        SWFFixture.Tag(code: 12, body: stream(actions))
    }

    /// DoAction (12) over a hand-built byte stream, for malformed cases.
    static func doActionTag(bytes: Data) -> SWFFixture.Tag {
        SWFFixture.Tag(code: 12, body: bytes)
    }

    /// DoInitAction (59): `Sprite ID` UI16 then the action stream.
    static func doInitActionTag(spriteId: UInt16, _ actions: [Action]) -> SWFFixture.Tag {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(spriteId)
        var body = writer.bytes()
        body.append(stream(actions))
        return SWFFixture.Tag(code: 59, body: body)
    }

    /// CLIPACTIONS: reserved UI16, `AllEventFlags`, the handlers, then the
    /// all-zero `ClipActionEndFlag`. `version` picks the 2- or 4-byte flag word.
    static func clipActions(
        version: UInt8,
        allEvents: SWFClipEventFlags,
        handlers: [ClipHandler]
    ) -> Data {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(0)
        appendFlags(&writer, allEvents, version: version)
        for handler in handlers {
            appendFlags(&writer, handler.events, version: version)
            let extra = handler.keyCode == nil ? 0 : 1
            writer.appendUInt32LE(UInt32(handler.actions.count + extra))
            if let keyCode = handler.keyCode {
                writer.appendByte(keyCode)
            }
            writer.appendBytes(Array(handler.actions))
        }
        appendFlags(&writer, SWFClipEventFlags(rawValue: 0), version: version)
        return writer.bytes()
    }
}

// MARK: - Field writers

extension SWFActionFixture {
    private static func encode(_ value: PushValue) -> Data {
        var writer = SWFBitWriter()
        switch value {
        case let .string(text):
            writer.appendByte(0)
            appendString(&writer, text)
        case let .float(number):
            writer.appendByte(1)
            writer.appendUInt32LE(number.bitPattern)
        case .null:
            writer.appendByte(2)
        case .undefined:
            writer.appendByte(3)
        case let .register(number):
            writer.appendBytes([4, number])
        case let .boolean(flag):
            writer.appendBytes([5, flag ? 1 : 0])
        case let .double(number):
            writer.appendByte(6)
            // Flash writes the high-order 32-bit word first (see
            // `SWFActionOperandDecoder.readDouble`).
            writer.appendUInt32LE(UInt32(number.bitPattern >> 32))
            writer.appendUInt32LE(UInt32(number.bitPattern & 0xFFFF_FFFF))
        case let .integer(number):
            writer.appendByte(7)
            writer.appendUInt32LE(UInt32(bitPattern: number))
        case let .constant8(index):
            writer.appendBytes([8, index])
        case let .constant16(index):
            writer.appendByte(9)
            writer.appendUInt16LE(index)
        }
        return writer.bytes()
    }

    private static func appendFlags(
        _ writer: inout SWFBitWriter,
        _ flags: SWFClipEventFlags,
        version: UInt8
    ) {
        if version >= 6 {
            writer.appendUInt32LE(flags.rawValue)
        } else {
            writer.appendUInt16LE(UInt16(flags.rawValue & 0xFFFF))
        }
    }

    private static func appendString(_ writer: inout SWFBitWriter, _ text: String) {
        writer.appendBytes(Array(text.utf8))
        writer.appendByte(0)
    }
}
