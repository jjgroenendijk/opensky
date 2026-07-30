// Bounds-checked decoder for the big-endian Skyrim PEX 3.x layout documented
// by UESP. Malformed external bytes always become a typed `PexError`.

import Foundation

nonisolated struct PexDecoder {
    var reader: PexReader
    var strings: [String] = []

    init(data: Data) {
        reader = PexReader(data)
    }

    mutating func decode() throws -> PexFile {
        let header = try decodeHeader()
        strings = try decodeStrings()
        let debugInfo = try decodeDebugInfo()
        let userFlags = try decodeUserFlags()
        let objects = try decodeObjects()
        guard reader.bytesRemaining == 0 else {
            throw PexError.trailingBytes(reader.bytesRemaining)
        }
        return PexFile(
            header: header,
            strings: strings,
            debugInfo: debugInfo,
            userFlags: userFlags,
            objects: objects
        )
    }

    private mutating func decodeHeader() throws -> PexHeader {
        let magic = try reader.readUInt32()
        guard magic == PexFile.magic else {
            throw PexError.invalidMagic(magic)
        }
        let major = try reader.readUInt8()
        let minor = try reader.readUInt8()
        guard major == 3, minor <= 2 else {
            throw PexError.unsupportedVersion(major: major, minor: minor)
        }
        let gameID = try reader.readUInt16()
        guard gameID == 1 else {
            throw PexError.unsupportedGameID(gameID)
        }
        return try PexHeader(
            majorVersion: major,
            minorVersion: minor,
            gameID: gameID,
            compilationTime: reader.readUInt64(),
            sourceFileName: reader.readString(),
            userName: reader.readString(),
            machineName: reader.readString()
        )
    }

    private mutating func decodeStrings() throws -> [String] {
        let count = try Int(reader.readUInt16())
        var result: [String] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            try result.append(reader.readString())
        }
        return result
    }

    private mutating func decodeDebugInfo() throws -> PexDebugInfo? {
        guard try reader.readUInt8() != 0 else {
            return nil
        }
        let modificationTime = try reader.readUInt64()
        let count = try Int(reader.readUInt16())
        var functions: [PexDebugFunction] = []
        functions.reserveCapacity(count)
        for _ in 0 ..< count {
            let objectName = try resolve(reader.readUInt16())
            let stateName = try resolve(reader.readUInt16())
            let functionName = try resolve(reader.readUInt16())
            let functionType = try reader.readUInt8()
            guard functionType <= 3 else {
                throw PexError.invalidDebugFunctionType(functionType)
            }
            let lineCount = try Int(reader.readUInt16())
            var lineNumbers: [UInt16] = []
            lineNumbers.reserveCapacity(lineCount)
            for _ in 0 ..< lineCount {
                try lineNumbers.append(reader.readUInt16())
            }
            functions.append(PexDebugFunction(
                objectName: objectName,
                stateName: stateName,
                functionName: functionName,
                functionType: functionType,
                lineNumbers: lineNumbers
            ))
        }
        return PexDebugInfo(modificationTime: modificationTime, functions: functions)
    }

    private mutating func decodeUserFlags() throws -> [PexUserFlag] {
        let count = try Int(reader.readUInt16())
        var flags: [PexUserFlag] = []
        flags.reserveCapacity(count)
        for _ in 0 ..< count {
            try flags.append(PexUserFlag(
                name: resolve(reader.readUInt16()),
                bitIndex: reader.readUInt8()
            ))
        }
        return flags
    }

    func resolve(_ index: UInt16) throws -> String {
        guard Int(index) < strings.count else {
            throw PexError.stringIndexOutOfRange(index: index, count: strings.count)
        }
        return strings[Int(index)]
    }
}

/// Sequential big-endian reader private to the PEX decoder.
nonisolated struct PexReader {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var bytesRemaining: Int {
        max(0, data.count - offset)
    }

    mutating func readUInt8() throws -> UInt8 {
        try read(count: 1)[0]
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try read(count: 2)
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try read(count: 4)
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    mutating func readUInt64() throws -> UInt64 {
        let bytes = try read(count: 8)
        return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func readInt32() throws -> Int32 {
        try Int32(bitPattern: readUInt32())
    }

    mutating func readFloat32() throws -> Float {
        try Float(bitPattern: readUInt32())
    }

    mutating func readString() throws -> String {
        let length = try Int(readUInt16())
        let stringOffset = offset
        let bytes = try read(count: length)
        guard let value = String(data: bytes, encoding: .utf8) else {
            throw PexError.invalidString(offset: stringOffset)
        }
        return value
    }

    mutating func subreader(count: Int) throws -> PexReader {
        try PexReader(read(count: count))
    }

    private mutating func read(count: Int) throws -> Data {
        guard count >= 0, offset >= 0, offset + count <= data.count else {
            throw PexError.truncated(
                offset: offset,
                expected: count,
                available: bytesRemaining
            )
        }
        let start = data.startIndex + offset
        let result = data.subdata(in: start ..< start + count)
        offset += count
        return result
    }
}
