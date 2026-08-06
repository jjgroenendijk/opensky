// ActionScript 1/2 opcode-code -> name table for the SWF 3-7 action model, the
// action-stream counterpart of `SWFTagName`. Used to report a known/unknown
// opcode tally when sweeping the game's Interface .swf files, and to name
// records in diagnostics.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — the SWF 3 / SWF 4 / SWF 5 / SWF 6 / SWF 7 action-model sections
// (pp. 63-118). Every code below is the `ActionCode` of an ACTIONRECORDHEADER
// named there, plus code 0 (the `ActionEndFlag` that terminates a stream).
//
// Scaleform GFx, the runtime Skyrim's UI actually targets, executes this same
// AS2 bytecode; its extensions are host objects and methods reached through
// ActionGetMember/ActionCallMethod, not new opcodes. So an unknown opcode here
// means a malformed or non-Adobe stream, not a GFx feature.

import Foundation

nonisolated enum SWFActionName {
    /// Human-readable name for a standard Adobe action code, or `nil` when the
    /// code is not in the Adobe specification (reserved or malformed).
    static func name(forCode code: UInt8) -> String? {
        names[code]
    }

    /// Whether `code` is a standard Adobe ActionScript 1/2 opcode.
    static func isKnown(_ code: UInt8) -> Bool {
        names[code] != nil
    }

    /// Every opcode the Adobe specification names, code-ascending.
    static var knownCodes: [UInt8] {
        names.keys.sorted()
    }

    /// The spec prints code 0x08 as "ActionToggleQualty"; that is a typographic
    /// error in the document, and the action is named ActionToggleQuality
    /// everywhere else (including Adobe's own tooling), so the corrected
    /// spelling is used here.
    private static let names: [UInt8: String] = [
        0x00: "ActionEnd",
        0x04: "ActionNextFrame",
        0x05: "ActionPrevFrame",
        0x06: "ActionPlay",
        0x07: "ActionStop",
        0x08: "ActionToggleQuality",
        0x09: "ActionStopSounds",
        0x0A: "ActionAdd",
        0x0B: "ActionSubtract",
        0x0C: "ActionMultiply",
        0x0D: "ActionDivide",
        0x0E: "ActionEquals",
        0x0F: "ActionLess",
        0x10: "ActionAnd",
        0x11: "ActionOr",
        0x12: "ActionNot",
        0x13: "ActionStringEquals",
        0x14: "ActionStringLength",
        0x15: "ActionStringExtract",
        0x17: "ActionPop",
        0x18: "ActionToInteger",
        0x1C: "ActionGetVariable",
        0x1D: "ActionSetVariable",
        0x20: "ActionSetTarget2",
        0x21: "ActionStringAdd",
        0x22: "ActionGetProperty",
        0x23: "ActionSetProperty",
        0x24: "ActionCloneSprite",
        0x25: "ActionRemoveSprite",
        0x26: "ActionTrace",
        0x27: "ActionStartDrag",
        0x28: "ActionEndDrag",
        0x29: "ActionStringLess",
        0x2A: "ActionThrow",
        0x2B: "ActionCastOp",
        0x2C: "ActionImplementsOp",
        0x30: "ActionRandomNumber",
        0x31: "ActionMBStringLength",
        0x32: "ActionCharToAscii",
        0x33: "ActionAsciiToChar",
        0x34: "ActionGetTime",
        0x35: "ActionMBStringExtract",
        0x36: "ActionMBCharToAscii",
        0x37: "ActionMBAsciiToChar",
        0x3A: "ActionDelete",
        0x3B: "ActionDelete2",
        0x3C: "ActionDefineLocal",
        0x3D: "ActionCallFunction",
        0x3E: "ActionReturn",
        0x3F: "ActionModulo",
        0x40: "ActionNewObject",
        0x41: "ActionDefineLocal2",
        0x42: "ActionInitArray",
        0x43: "ActionInitObject",
        0x44: "ActionTypeOf",
        0x45: "ActionTargetPath",
        0x46: "ActionEnumerate",
        0x47: "ActionAdd2",
        0x48: "ActionLess2",
        0x49: "ActionEquals2",
        0x4A: "ActionToNumber",
        0x4B: "ActionToString",
        0x4C: "ActionPushDuplicate",
        0x4D: "ActionStackSwap",
        0x4E: "ActionGetMember",
        0x4F: "ActionSetMember",
        0x50: "ActionIncrement",
        0x51: "ActionDecrement",
        0x52: "ActionCallMethod",
        0x53: "ActionNewMethod",
        0x54: "ActionInstanceOf",
        0x55: "ActionEnumerate2",
        0x60: "ActionBitAnd",
        0x61: "ActionBitOr",
        0x62: "ActionBitXor",
        0x63: "ActionBitLShift",
        0x64: "ActionBitRShift",
        0x65: "ActionBitURShift",
        0x66: "ActionStrictEquals",
        0x67: "ActionGreater",
        0x68: "ActionStringGreater",
        0x69: "ActionExtends",
        0x81: "ActionGotoFrame",
        0x83: "ActionGetURL",
        0x87: "ActionStoreRegister",
        0x88: "ActionConstantPool",
        0x8A: "ActionWaitForFrame",
        0x8B: "ActionSetTarget",
        0x8C: "ActionGoToLabel",
        0x8D: "ActionWaitForFrame2",
        0x8E: "ActionDefineFunction2",
        0x8F: "ActionTry",
        0x94: "ActionWith",
        0x96: "ActionPush",
        0x99: "ActionJump",
        0x9A: "ActionGetURL2",
        0x9B: "ActionDefineFunction",
        0x9D: "ActionIf",
        0x9E: "ActionCall",
        0x9F: "ActionGotoFrame2"
    ]
}
