// The action codes this interpreter implements (milestone 8.3.2), named so the
// dispatch tables read as bytecode rather than as hexadecimal.
//
// The set is closed by measurement, not by guess: `openskycli swf action-sweep`
// over the 53 vanilla `Interface/*.swf` movies found 533,562 action records
// using exactly 56 distinct opcodes and no unknown code (docs/formats/swf-actions.md,
// "Vanilla bytecode"). Those 56 are all here, plus `ActionDefineLocal2`
// and `ActionStackSwap`, which cost two lines each and are reachable from any
// compiler.
//
// Deliberately absent, because no vanilla movie uses them: `ActionWith`,
// `ActionTry`/`ActionThrow`, `ActionSetTarget`/`ActionSetTarget2`,
// `ActionGetURL`/`ActionGetURL2`, `ActionWaitForFrame`/`ActionWaitForFrame2`,
// and `ActionEnumerate` (only `ActionEnumerate2` occurs). They frame correctly
// in `SWFActionParser` and execute as a tallied no-op here.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions", the per-action tables in the SWF 3 through SWF 7 action-model
// sections (pp. 63-118). Names match `SWFActionName`.

import Foundation

nonisolated package enum AS2Opcode {
    // Stack and constants
    package static let push: UInt8 = 0x96
    package static let pop: UInt8 = 0x17
    package static let pushDuplicate: UInt8 = 0x4C
    package static let stackSwap: UInt8 = 0x4D
    package static let storeRegister: UInt8 = 0x87
    package static let constantPool: UInt8 = 0x88

    // Arithmetic
    package static let subtract: UInt8 = 0x0B
    package static let multiply: UInt8 = 0x0C
    package static let divide: UInt8 = 0x0D
    package static let modulo: UInt8 = 0x3F
    package static let add2: UInt8 = 0x47
    package static let increment: UInt8 = 0x50
    package static let decrement: UInt8 = 0x51
    package static let toNumber: UInt8 = 0x4A
    package static let toString: UInt8 = 0x4B

    // Comparison and logic
    package static let not: UInt8 = 0x12
    package static let equals2: UInt8 = 0x49
    package static let strictEquals: UInt8 = 0x66
    package static let less2: UInt8 = 0x48
    package static let greater: UInt8 = 0x67

    // Bitwise
    package static let bitAnd: UInt8 = 0x60
    package static let bitOr: UInt8 = 0x61
    package static let bitXor: UInt8 = 0x62
    package static let bitLShift: UInt8 = 0x63
    package static let bitRShift: UInt8 = 0x64
    package static let bitURShift: UInt8 = 0x65

    // Variables and members
    package static let getVariable: UInt8 = 0x1C
    package static let setVariable: UInt8 = 0x1D
    package static let getMember: UInt8 = 0x4E
    package static let setMember: UInt8 = 0x4F
    package static let defineLocal: UInt8 = 0x3C
    package static let defineLocal2: UInt8 = 0x41
    package static let delete: UInt8 = 0x3A
    package static let delete2: UInt8 = 0x3B

    // Object structure
    package static let initObject: UInt8 = 0x43
    package static let initArray: UInt8 = 0x42
    package static let enumerate2: UInt8 = 0x55
    package static let typeOf: UInt8 = 0x44
    package static let instanceOf: UInt8 = 0x54
    package static let extends: UInt8 = 0x69
    package static let castOp: UInt8 = 0x2B

    // Calls and functions
    package static let callFunction: UInt8 = 0x3D
    package static let callMethod: UInt8 = 0x52
    package static let newObject: UInt8 = 0x40
    package static let newMethod: UInt8 = 0x53
    package static let returnValue: UInt8 = 0x3E
    package static let defineFunction: UInt8 = 0x9B
    package static let defineFunction2: UInt8 = 0x8E

    // Control flow
    package static let jump: UInt8 = 0x99
    package static let branchIfTrue: UInt8 = 0x9D

    // Host and timeline
    package static let play: UInt8 = 0x06
    package static let stop: UInt8 = 0x07
    package static let gotoFrame: UInt8 = 0x81
    package static let goToLabel: UInt8 = 0x8C
    package static let getProperty: UInt8 = 0x22
    package static let setProperty: UInt8 = 0x23
    package static let targetPath: UInt8 = 0x45
    package static let trace: UInt8 = 0x26

    /// Every opcode the dispatch tables handle, for the coverage test that
    /// pins this set against `SWFActionName`.
    package static let implemented: Set<UInt8> = [
        push, pop, pushDuplicate, stackSwap, storeRegister, constantPool,
        subtract, multiply, divide, modulo, add2, increment, decrement,
        toNumber, toString, not, equals2, strictEquals, less2, greater,
        bitAnd, bitOr, bitXor, bitLShift, bitRShift, bitURShift,
        getVariable, setVariable, getMember, setMember, defineLocal,
        defineLocal2, delete, delete2, initObject, initArray, enumerate2,
        typeOf, instanceOf, extends, castOp, callFunction, callMethod,
        newObject, newMethod, returnValue, defineFunction, defineFunction2,
        jump, branchIfTrue, play, stop, gotoFrame, goToLabel, getProperty,
        setProperty, targetPath, trace
    ]
}
