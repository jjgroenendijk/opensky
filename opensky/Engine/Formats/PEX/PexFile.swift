// Skyrim compiled Papyrus script container.
//
// Layout source: UESP "Skyrim Mod:Compiled Script File Format"
// https://en.uesp.net/wiki/Skyrim_Mod:Compiled_Script_File_Format
// The source documents big-endian PEX 3.x framing. A 2026-07-30 probe of the
// user's base-game, DLC and Creation archives confirmed version 3.2 uses the
// same layout, including the 0xFA57C0DE magic and game ID 1.

import Foundation

nonisolated enum PexError: Error, Equatable {
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

nonisolated struct PexHeader: Equatable, Sendable {
    let majorVersion: UInt8
    let minorVersion: UInt8
    let gameID: UInt16
    let compilationTime: UInt64
    let sourceFileName: String
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

nonisolated struct PexDebugInfo: Equatable, Sendable {
    let modificationTime: UInt64
    let functions: [PexDebugFunction]
}

nonisolated struct PexUserFlag: Equatable, Sendable {
    let name: String
    let bitIndex: UInt8
}

nonisolated struct PexFile: Equatable, Sendable {
    static let magic: UInt32 = 0xFA57_C0DE

    let header: PexHeader
    let strings: [String]
    let debugInfo: PexDebugInfo?
    let userFlags: [PexUserFlag]
    let objects: [PexObject]

    init(data: Data) throws {
        var decoder = PexDecoder(data: data)
        self = try decoder.decode()
    }

    init(
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
