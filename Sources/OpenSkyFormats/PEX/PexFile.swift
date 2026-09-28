// Skyrim compiled Papyrus script container.
//
// Layout source: UESP "Skyrim Mod:Compiled Script File Format"
// https://en.uesp.net/wiki/Skyrim_Mod:Compiled_Script_File_Format
// The source documents big-endian PEX 3.x framing. A 2026-07-30 probe of the
// user's base-game, DLC and Creation archives confirmed version 3.2 uses the
// same layout, including the 0xFA57C0DE magic and game ID 1.

import Foundation

nonisolated package enum PexError: Error, Equatable {
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

nonisolated package struct PexHeader: Equatable, Sendable {
    package let majorVersion: UInt8
    package let minorVersion: UInt8
    package let gameID: UInt16
    package let compilationTime: UInt64
    package let sourceFileName: String
    package let userName: String
    package let machineName: String
}

nonisolated package struct PexDebugFunction: Equatable, Sendable {
    package let objectName: String
    package let stateName: String
    package let functionName: String
    package let functionType: UInt8
    package let lineNumbers: [UInt16]
}

nonisolated package struct PexDebugInfo: Equatable, Sendable {
    package let modificationTime: UInt64
    package let functions: [PexDebugFunction]
}

nonisolated package struct PexUserFlag: Equatable, Sendable {
    package let name: String
    package let bitIndex: UInt8
}

nonisolated package struct PexFile: Equatable, Sendable {
    package static let magic: UInt32 = 0xFA57_C0DE

    package let header: PexHeader
    package let strings: [String]
    package let debugInfo: PexDebugInfo?
    package let userFlags: [PexUserFlag]
    package let objects: [PexObject]

    package init(data: Data) throws {
        var decoder = PexDecoder(data: data)
        self = try decoder.decode()
    }

    package init(
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
