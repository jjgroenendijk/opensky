// Compiled Papyrus script container (big-endian PEX 3.2).
// Layout and sources: docs/formats/pex.md.

import Foundation

nonisolated public enum PexError: Error, Equatable, Sendable {
    case truncated(offset: Int, expected: Int, available: Int)
    case invalidMagic(UInt32)
    case unsupportedVersion(major: UInt8, minor: UInt8)
    case unsupportedGameID(UInt16)
    case stringIndexOutOfRange(index: UInt16, count: Int)
    case invalidValueType(UInt8)
    case invalidDebugFunctionType(UInt8)
    case invalidObjectSize(UInt32)
    case objectSizeMismatch(name: String, remaining: Int)
    case invalidVarargCount(PexValue)
    case trailingBytes(Int)
}

nonisolated public struct PexHeader: Equatable, Sendable {
    public let majorVersion: UInt8
    public let minorVersion: UInt8
    let gameID: UInt16
    let compilationTime: UInt64
    public let sourceFileName: String
    let userName: String
    let machineName: String
}

nonisolated struct PexDebugFunction: Equatable, Sendable {
    let objectName: String
    let stateName: String
    let functionName: String
    let functionType: UInt8
    let lineNumbers: [UInt16]
}

nonisolated public struct PexDebugInfo: Equatable, Sendable {
    let modificationTime: UInt64
    let functions: [PexDebugFunction]
}

nonisolated public struct PexUserFlag: Equatable, Sendable {
    let name: String
    let bitIndex: UInt8
}

nonisolated public struct PexFile: Equatable, Sendable {
    public static let magic: UInt32 = 0xFA57_C0DE

    public let header: PexHeader
    public let strings: [String]
    public let debugInfo: PexDebugInfo?
    public let userFlags: [PexUserFlag]
    public let objects: [PexObject]

    public init(
        header: PexHeader,
        strings: [String],
        debugInfo: PexDebugInfo?,
        userFlags: [PexUserFlag],
        objects: [PexObject]
    ) {
        self.header = header
        self.strings = strings
        self.debugInfo = debugInfo
        self.userFlags = userFlags
        self.objects = objects
    }
}
