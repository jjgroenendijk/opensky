// The `.ess` header and screenshot: everything before the body, which a save list
// reads without decompressing anything. See docs/formats/ess.md#header.

import Foundation

nonisolated public enum ESSCompression: UInt16, Sendable {
    case none = 0
    case zlib = 1
    case lz4 = 2

    public var name: String {
        switch self {
        case .none: "none"
        case .zlib: "zlib"
        case .lz4: "LZ4"
        }
    }
}

nonisolated public struct ESSHeader: Equatable, Sendable {
    /// 7 to 9 for Legendary Edition, 12 for Special Edition.
    public let version: UInt32
    public let saveNumber: UInt32
    public let playerName: String
    public let playerLevel: UInt32
    public let playerLocation: String
    /// The in-game date as the game printed it, such as "Morndas, 17th of Last Seed".
    public let gameDate: String
    public let playerRaceEditorID: String
    public let isFemale: Bool
    public let experience: Float
    public let experienceForNextLevel: Float
    /// Windows `FILETIME`: 100 ns ticks since 1601-01-01 UTC.
    public let fileTime: UInt64
    public let screenshotWidth: Int
    public let screenshotHeight: Int
    public let compression: ESSCompression

    public static let magic = Data("TESV_SAVEGAME".utf8)
    public static let specialEditionVersion: UInt32 = 12
    public static let supportedVersions: Set<UInt32> = [7, 8, 9, 12]
    /// Largest screenshot side accepted, far above what the game writes.
    public static let maximumScreenshotSide = 4096

    public var isSpecialEdition: Bool {
        version >= Self.specialEditionVersion
    }

    /// Bytes per screenshot pixel: RGB before Special Edition, RGBA after.
    public var screenshotBytesPerPixel: Int {
        isSpecialEdition ? 4 : 3
    }

    /// The save time, or nil for a tick count no `Date` can hold.
    public var savedAt: Date? {
        let windowsEpochOffset: Double = 11_644_473_600
        let seconds = Double(fileTime) / 10_000_000 - windowsEpochOffset
        return seconds.isFinite ? Date(timeIntervalSince1970: seconds) : nil
    }
}

/// The screenshot, widened to RGBA8 rows top first. It is a frame of the user's game,
/// so it is shown, never committed.
nonisolated public struct ESSScreenshot: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: Data

    public init(width: Int, height: Int, rgba: Data) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

/// What a save list reads: the header, the screenshot, and where the body starts.
nonisolated public struct ESSSummary: Equatable, Sendable {
    public let header: ESSHeader
    public let screenshot: ESSScreenshot
    /// Offset of the first byte after the screenshot.
    public let bodyOffset: Int

    /// Reads the header and screenshot only.
    public init(data: Data) throws(ESSError) {
        var reader = ESSReader(data)
        guard try reader.bytes(ESSHeader.magic.count, "magic") == ESSHeader.magic else {
            throw .badMagic
        }
        let headerSize = try Int(reader.uint32("header size"))
        let headerStart = reader.offset
        guard headerSize <= reader.bytesRemaining else { throw .truncated(context: "header") }
        let header = try Self.readHeader(&reader)
        guard reader.offset - headerStart <= headerSize else {
            throw .invalidValue(context: "header fields run past the header size \(headerSize)")
        }
        reader.seek(to: headerStart + headerSize)
        screenshot = try Self.readScreenshot(&reader, header: header)
        self.header = header
        bodyOffset = reader.offset
    }

    private static func readHeader(_ reader: inout ESSReader) throws(ESSError) -> ESSHeader {
        let version = try reader.uint32("header version")
        guard ESSHeader.supportedVersions.contains(version) else {
            throw .unsupportedVersion(version)
        }
        let saveNumber = try reader.uint32("save number")
        let name = try reader.wstring("player name")
        let level = try reader.uint32("player level")
        let location = try reader.wstring("player location")
        let date = try reader.wstring("game date")
        let race = try reader.wstring("player race")
        let sex = try reader.uint16("player sex")
        let experience = try reader.float32("player experience")
        let nextLevel = try reader.float32("experience for next level")
        let fileTime = try reader.uint64("file time")
        let width = try Int(reader.uint32("screenshot width"))
        let height = try Int(reader.uint32("screenshot height"))
        var compression = ESSCompression.none
        if version >= ESSHeader.specialEditionVersion {
            let raw = try reader.uint16("compression type")
            guard let value = ESSCompression(rawValue: raw) else {
                throw .unsupportedCompression(raw)
            }
            compression = value
        }
        return ESSHeader(
            version: version, saveNumber: saveNumber, playerName: name, playerLevel: level,
            playerLocation: location, gameDate: date, playerRaceEditorID: race,
            isFemale: sex == 1, experience: experience, experienceForNextLevel: nextLevel,
            fileTime: fileTime, screenshotWidth: width, screenshotHeight: height,
            compression: compression
        )
    }

    private static func readScreenshot(
        _ reader: inout ESSReader, header: ESSHeader
    ) throws(ESSError) -> ESSScreenshot {
        let side = 0 ... ESSHeader.maximumScreenshotSide
        guard side.contains(header.screenshotWidth), side.contains(header.screenshotHeight)
        else {
            throw .invalidValue(
                context: "screenshot is \(header.screenshotWidth)x\(header.screenshotHeight)"
            )
        }
        let pixels = header.screenshotWidth * header.screenshotHeight
        let raw = try reader.bytes(pixels * header.screenshotBytesPerPixel, "screenshot")
        guard header.screenshotBytesPerPixel == 3 else {
            return ESSScreenshot(
                width: header.screenshotWidth, height: header.screenshotHeight, rgba: raw
            )
        }
        var rgba = Data(capacity: pixels * 4)
        var index = raw.startIndex
        for _ in 0 ..< pixels {
            rgba.append(contentsOf: raw[index ..< index + 3])
            rgba.append(0xFF)
            index += 3
        }
        return ESSScreenshot(
            width: header.screenshotWidth, height: header.screenshotHeight, rgba: rgba
        )
    }
}
