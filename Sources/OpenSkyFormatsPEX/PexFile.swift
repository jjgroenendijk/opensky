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
    public let gameID: UInt16
    public let compilationTime: UInt64
    public let sourceFileName: String
    public let userName: String
    public let machineName: String
}

nonisolated public struct PexDebugFunction: Equatable, Sendable {
    public let objectName: String
    public let stateName: String
    public let functionName: String
    public let functionType: UInt8
    public let lineNumbers: [UInt16]
}

nonisolated public struct PexDebugInfo: Equatable, Sendable {
    public let modificationTime: UInt64
    public let functions: [PexDebugFunction]
}

nonisolated public struct PexUserFlag: Equatable, Sendable {
    public let name: String
    public let bitIndex: UInt8
}

nonisolated public struct PexFile: Equatable, Sendable {
    public static let magic: UInt32 = 0xFA57_C0DE

    public let header: PexHeader
    public let strings: [String]
    public let debugInfo: PexDebugInfo?
    public let userFlags: [PexUserFlag]
    public let objects: [PexObject]

    public init(data: Data) throws {
        var decoder = PexDecoder(data: data)
        self = try decoder.decode()
    }

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
