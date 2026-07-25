// The action codes this interpreter implements (milestone 8.3.2), named so the
// dispatch tables read as bytecode rather than as hexadecimal.
//
// The set is closed by measurement, not by guess: `openskycli swf action-sweep`
// over the 53 vanilla `Interface/*.swf` movies found 533,562 action records
// using exactly 56 distinct opcodes and no unknown code (docs/formats/swf.md,
// "Vanilla sweep results"). Those 56 are all here, plus `ActionDefineLocal2`
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

nonisolated enum AS2Opcode {
    // Stack and constants
    static let push: UInt8 = 0x96
    static let pop: UInt8 = 0x17
    static let pushDuplicate: UInt8 = 0x4C
    static let stackSwap: UInt8 = 0x4D
    static let storeRegister: UInt8 = 0x87
    static let constantPool: UInt8 = 0x88

    // Arithmetic
    static let subtract: UInt8 = 0x0B
    static let multiply: UInt8 = 0x0C
    static let divide: UInt8 = 0x0D
    static let modulo: UInt8 = 0x3F
    static let add2: UInt8 = 0x47
    static let increment: UInt8 = 0x50
    static let decrement: UInt8 = 0x51
    static let toNumber: UInt8 = 0x4A
    static let toString: UInt8 = 0x4B

    // Comparison and logic
    static let not: UInt8 = 0x12
    static let equals2: UInt8 = 0x49
    static let strictEquals: UInt8 = 0x66
    static let less2: UInt8 = 0x48
    static let greater: UInt8 = 0x67

    // Bitwise
    static let bitAnd: UInt8 = 0x60
    static let bitOr: UInt8 = 0x61
    static let bitXor: UInt8 = 0x62
    static let bitLShift: UInt8 = 0x63
    static let bitRShift: UInt8 = 0x64
    static let bitURShift: UInt8 = 0x65

    // Variables and members
    static let getVariable: UInt8 = 0x1C
    static let setVariable: UInt8 = 0x1D
    static let getMember: UInt8 = 0x4E
    static let setMember: UInt8 = 0x4F
    static let defineLocal: UInt8 = 0x3C
    static let defineLocal2: UInt8 = 0x41
    static let delete: UInt8 = 0x3A
    static let delete2: UInt8 = 0x3B

    // Object structure
    static let initObject: UInt8 = 0x43
    static let initArray: UInt8 = 0x42
    static let enumerate2: UInt8 = 0x55
    static let typeOf: UInt8 = 0x44
    static let instanceOf: UInt8 = 0x54
    static let extends: UInt8 = 0x69
    static let castOp: UInt8 = 0x2B

    // Calls and functions
    static let callFunction: UInt8 = 0x3D
    static let callMethod: UInt8 = 0x52
    static let newObject: UInt8 = 0x40
    static let newMethod: UInt8 = 0x53
    static let returnValue: UInt8 = 0x3E
    static let defineFunction: UInt8 = 0x9B
    static let defineFunction2: UInt8 = 0x8E

    // Control flow
    static let jump: UInt8 = 0x99
    static let branchIfTrue: UInt8 = 0x9D

    // Host and timeline
    static let play: UInt8 = 0x06
    static let stop: UInt8 = 0x07
    static let gotoFrame: UInt8 = 0x81
    static let goToLabel: UInt8 = 0x8C
    static let getProperty: UInt8 = 0x22
    static let setProperty: UInt8 = 0x23
    static let targetPath: UInt8 = 0x45
    static let trace: UInt8 = 0x26

    /// Every opcode the dispatch tables handle, for the coverage test that
    /// pins this set against `SWFActionName`.
    static let implemented: Set<UInt8> = [
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
