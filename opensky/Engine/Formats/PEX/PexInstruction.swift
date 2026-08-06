// Typed Papyrus instruction model for Skyrim's PEX 3.x bytecode.
//
// Layout: UESP "Skyrim Mod:Compiled Script File Format", Instruction and
// Opcodes. The parser preserves an unknown raw byte instead of rejecting the
// whole script; the interpreter decides whether executing it is a fault.

import Foundation

nonisolated enum PexValue: Equatable, Sendable {
    case null
    case identifier(String)
    case string(String)
    case integer(Int32)
    case float(Float)
    case boolean(Bool)

    var stringValue: String? {
        switch self {
        case let .identifier(value), let .string(value):
            value
        default:
            nil
        }
    }
}

nonisolated enum PexOpcode: Equatable, Hashable, Sendable {
    case nop
    case integerAdd
    case floatAdd
    case integerSubtract
    case floatSubtract
    case integerMultiply
    case floatMultiply
    case integerDivide
    case floatDivide
    case integerModulo
    case not
    case integerNegate
    case floatNegate
    case assign
    case cast
    case compareEqual
    case compareLess
    case compareLessOrEqual
    case compareGreater
    case compareGreaterOrEqual
    case jump
    case jumpTrue
    case jumpFalse
    case callMethod
    case callParent
    case callStatic
    case returnValue
    case stringConcatenate
    case propertyGet
    case propertySet
    case arrayCreate
    case arrayLength
    case arrayGetElement
    case arraySetElement
    case arrayFindElement
    case arrayReverseFindElement
    case unknown(UInt8)

    private static let knownOpcodes: [PexOpcode] = [
        .nop,
        .integerAdd,
        .floatAdd,
        .integerSubtract,
        .floatSubtract,
        .integerMultiply,
        .floatMultiply,
        .integerDivide,
        .floatDivide,
        .integerModulo,
        .not,
        .integerNegate,
        .floatNegate,
        .assign,
        .cast,
        .compareEqual,
        .compareLess,
        .compareLessOrEqual,
        .compareGreater,
        .compareGreaterOrEqual,
        .jump,
        .jumpTrue,
        .jumpFalse,
        .callMethod,
        .callParent,
        .callStatic,
        .returnValue,
        .stringConcatenate,
        .propertyGet,
        .propertySet,
        .arrayCreate,
        .arrayLength,
        .arrayGetElement,
        .arraySetElement,
        .arrayFindElement,
        .arrayReverseFindElement
    ]

    init(rawValue: UInt8) {
        if Int(rawValue) < Self.knownOpcodes.count {
            self = Self.knownOpcodes[Int(rawValue)]
        } else {
            self = .unknown(rawValue)
        }
    }

    var rawValue: UInt8 {
        switch self {
        case .nop: 0x00
        case .integerAdd: 0x01
        case .floatAdd: 0x02
        case .integerSubtract: 0x03
        case .floatSubtract: 0x04
        case .integerMultiply: 0x05
        case .floatMultiply: 0x06
        case .integerDivide: 0x07
        case .floatDivide: 0x08
        case .integerModulo: 0x09
        case .not: 0x0A
        case .integerNegate: 0x0B
        case .floatNegate: 0x0C
        case .assign: 0x0D
        case .cast: 0x0E
        case .compareEqual: 0x0F
        case .compareLess: 0x10
        case .compareLessOrEqual: 0x11
        case .compareGreater: 0x12
        case .compareGreaterOrEqual: 0x13
        case .jump: 0x14
        case .jumpTrue: 0x15
        case .jumpFalse: 0x16
        case .callMethod: 0x17
        case .callParent: 0x18
        case .callStatic: 0x19
        case .returnValue: 0x1A
        case .stringConcatenate: 0x1B
        case .propertyGet: 0x1C
        case .propertySet: 0x1D
        case .arrayCreate: 0x1E
        case .arrayLength: 0x1F
        case .arrayGetElement: 0x20
        case .arraySetElement: 0x21
        case .arrayFindElement: 0x22
        case .arrayReverseFindElement: 0x23
        case let .unknown(raw): raw
        }
    }

    var name: String {
        switch self {
        case .nop: "nop"
        case .integerAdd: "iadd"
        case .floatAdd: "fadd"
        case .integerSubtract: "isub"
        case .floatSubtract: "fsub"
        case .integerMultiply: "imul"
        case .floatMultiply: "fmul"
        case .integerDivide: "idiv"
        case .floatDivide: "fdiv"
        case .integerModulo: "imod"
        case .not: "not"
        case .integerNegate: "ineg"
        case .floatNegate: "fneg"
        case .assign: "assign"
        case .cast: "cast"
        case .compareEqual: "cmp_eq"
        case .compareLess: "cmp_lt"
        case .compareLessOrEqual: "cmp_le"
        case .compareGreater: "cmp_gt"
        case .compareGreaterOrEqual: "cmp_ge"
        case .jump: "jmp"
        case .jumpTrue: "jmpt"
        case .jumpFalse: "jmpf"
        case .callMethod: "callmethod"
        case .callParent: "callparent"
        case .callStatic: "callstatic"
        case .returnValue: "return"
        case .stringConcatenate: "strcat"
        case .propertyGet: "propget"
        case .propertySet: "propset"
        case .arrayCreate: "array_create"
        case .arrayLength: "array_length"
        case .arrayGetElement: "array_getelement"
        case .arraySetElement: "array_setelement"
        case .arrayFindElement: "array_findelement"
        case .arrayReverseFindElement: "array_rfindelement"
        case let .unknown(raw): String(format: "unknown(0x%02X)", raw)
        }
    }

    /// Operand count before any call's integer vararg count and arguments.
    var fixedOperandCount: Int {
        switch self {
        case .nop, .unknown:
            0
        case .jump, .returnValue:
            1
        case .not, .integerNegate, .floatNegate, .assign, .cast, .jumpTrue, .jumpFalse:
            2
        case .callParent:
            2
        case .callMethod, .callStatic:
            3
        case .integerAdd, .floatAdd, .integerSubtract, .floatSubtract,
             .integerMultiply, .floatMultiply, .integerDivide, .floatDivide,
             .integerModulo, .compareEqual, .compareLess, .compareLessOrEqual,
             .compareGreater, .compareGreaterOrEqual, .stringConcatenate,
             .propertyGet, .propertySet, .arrayGetElement, .arraySetElement:
            3
        case .arrayCreate, .arrayLength:
            2
        case .arrayFindElement, .arrayReverseFindElement:
            4
        }
    }

    var hasVarargs: Bool {
        self == .callMethod || self == .callParent || self == .callStatic
    }
}

nonisolated struct PexInstruction: Equatable, Sendable {
    let opcode: PexOpcode
    /// Fixed operands followed by the call count value and call arguments.
    let operands: [PexValue]
}
