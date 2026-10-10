// The action codes this interpreter runs. The set comes from a sweep of the
// vanilla movies (docs/formats/swf-actions.md, "Vanilla bytecode"), plus
// `ActionDefineLocal2` and `ActionStackSwap`. Unused actions such as
// `ActionWith` run as a tallied no-op. Spec: SWF v19 chapter 5.

import Foundation

nonisolated public enum AS2Opcode: Sendable {
    // Stack and constants
    public static let push: UInt8 = 0x96
    public static let pop: UInt8 = 0x17
    public static let pushDuplicate: UInt8 = 0x4C
    public static let stackSwap: UInt8 = 0x4D
    public static let storeRegister: UInt8 = 0x87
    public static let constantPool: UInt8 = 0x88

    // Arithmetic
    public static let subtract: UInt8 = 0x0B
    public static let multiply: UInt8 = 0x0C
    public static let divide: UInt8 = 0x0D
    public static let modulo: UInt8 = 0x3F
    public static let add2: UInt8 = 0x47
    public static let increment: UInt8 = 0x50
    public static let decrement: UInt8 = 0x51
    public static let toNumber: UInt8 = 0x4A
    public static let toString: UInt8 = 0x4B

    // Comparison and logic
    public static let not: UInt8 = 0x12
    public static let equals2: UInt8 = 0x49
    public static let strictEquals: UInt8 = 0x66
    public static let less2: UInt8 = 0x48
    public static let greater: UInt8 = 0x67

    // Bitwise
    public static let bitAnd: UInt8 = 0x60
    public static let bitOr: UInt8 = 0x61
    public static let bitXor: UInt8 = 0x62
    public static let bitLShift: UInt8 = 0x63
    public static let bitRShift: UInt8 = 0x64
    public static let bitURShift: UInt8 = 0x65

    // Variables and members
    public static let getVariable: UInt8 = 0x1C
    public static let setVariable: UInt8 = 0x1D
    public static let getMember: UInt8 = 0x4E
    public static let setMember: UInt8 = 0x4F
    public static let defineLocal: UInt8 = 0x3C
    public static let defineLocal2: UInt8 = 0x41
    public static let delete: UInt8 = 0x3A
    public static let delete2: UInt8 = 0x3B

    // Object structure
    public static let initObject: UInt8 = 0x43
    public static let initArray: UInt8 = 0x42
    public static let enumerate2: UInt8 = 0x55
    public static let typeOf: UInt8 = 0x44
    public static let instanceOf: UInt8 = 0x54
    public static let extends: UInt8 = 0x69
    public static let castOp: UInt8 = 0x2B

    // Calls and functions
    public static let callFunction: UInt8 = 0x3D
    public static let callMethod: UInt8 = 0x52
    public static let newObject: UInt8 = 0x40
    public static let newMethod: UInt8 = 0x53
    public static let returnValue: UInt8 = 0x3E
    public static let defineFunction: UInt8 = 0x9B
    public static let defineFunction2: UInt8 = 0x8E

    // Control flow
    public static let jump: UInt8 = 0x99
    public static let branchIfTrue: UInt8 = 0x9D

    // Host and timeline
    public static let play: UInt8 = 0x06
    public static let stop: UInt8 = 0x07
    public static let gotoFrame: UInt8 = 0x81
    public static let goToLabel: UInt8 = 0x8C
    public static let getProperty: UInt8 = 0x22
    public static let setProperty: UInt8 = 0x23
    public static let targetPath: UInt8 = 0x45
    public static let trace: UInt8 = 0x26

    /// Every opcode the dispatch tables handle, for the coverage test that
    /// pins this set against `SWFActionName`.
    public static let implemented: Set<UInt8> = [
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
