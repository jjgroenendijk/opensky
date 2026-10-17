// Writes a whole `.ess`: header, screenshot, and a body laid out as the game lays it out,
// with the file location table computed from the parts. Special Edition saves compress
// the body as one raw LZ4 block. See docs/formats/ess.md#writing.

import Foundation
import OpenSkyFormatsCore

/// Everything a save file holds, in file order. `ESSFile` is its read side.
nonisolated public struct ESSFileContents: Equatable, Sendable {
    public var header: ESSHeader
    /// RGBA8 rows, top first. Its size must match the header's screenshot size.
    public var screenshot: ESSScreenshot
    public var formVersion: UInt8
    public var plugins: [String]
    public var lightPlugins: [String]
    public var globalData1: [ESSGlobalData]
    public var globalData2: [ESSGlobalData]
    public var changeForms: [ESSChangeForm]
    public var globalData3: [ESSGlobalData]
    public var formIDArray: [UInt32]
    public var visitedWorldspaces: [UInt32]

    /// Special Edition 1.5.97 and later with light plugins.
    public static let currentFormVersion: UInt8 = 78

    public init(
        header: ESSHeader, screenshot: ESSScreenshot,
        formVersion: UInt8 = Self.currentFormVersion, plugins: [String],
        lightPlugins: [String] = [], globalData1: [ESSGlobalData] = [],
        globalData2: [ESSGlobalData] = [], changeForms: [ESSChangeForm] = [],
        globalData3: [ESSGlobalData] = [], formIDArray: [UInt32] = [],
        visitedWorldspaces: [UInt32] = []
    ) {
        self.header = header
        self.screenshot = screenshot
        self.formVersion = formVersion
        self.plugins = plugins
        self.lightPlugins = lightPlugins
        self.globalData1 = globalData1
        self.globalData2 = globalData2
        self.changeForms = changeForms
        self.globalData3 = globalData3
        self.formIDArray = formIDArray
        self.visitedWorldspaces = visitedWorldspaces
    }

    /// The file bytes. Same contents, same bytes.
    public func encoded() throws(ESSError) -> Data {
        guard header.isSpecialEdition else { throw .unsupportedVersion(header.version) }
        guard ESSFile.supportedFormVersions.contains(formVersion) else {
            throw .unsupportedFormVersion(formVersion)
        }
        let headerBytes = try headerData()
        let pixels = try screenshotData()
        let bodyStart = ESSHeader.magic.count + 4 + headerBytes.count + pixels.count
        let body = try bodyData(bodyStart: bodyStart)
        var file = ESSWriter()
        file.bytes(ESSHeader.magic)
        try file.count32(headerBytes.count, "header size")
        file.bytes(headerBytes)
        file.bytes(pixels)
        switch header.compression {
        case .none:
            file.bytes(body)
        case .zlib:
            // UESP: the game does not write zlib bodies, so OpenSky does not either.
            throw .unsupportedCompression(header.compression.rawValue)
        case .lz4:
            let packed = try Self.lz4(body)
            try file.count32(body.count, "uncompressed length")
            try file.count32(packed.count, "compressed length")
            file.bytes(packed)
        }
        return file.data
    }

    private static func lz4(_ body: Data) throws(ESSError) -> Data {
        do {
            return try LZ4.compressRawBlock(body)
        } catch {
            throw .decompressionFailed(context: "LZ4 compression: \(error)")
        }
    }

    private func headerData() throws(ESSError) -> Data {
        try ESSWriter.build { writer throws(ESSError) in
            writer.uint32(header.version)
            writer.uint32(header.saveNumber)
            try writer.wstring(header.playerName, "player name")
            writer.uint32(header.playerLevel)
            try writer.wstring(header.playerLocation, "player location")
            try writer.wstring(header.gameDate, "game date")
            try writer.wstring(header.playerRaceEditorID, "player race")
            writer.uint16(header.isFemale ? 1 : 0)
            writer.float32(header.experience)
            writer.float32(header.experienceForNextLevel)
            writer.uint64(header.fileTime)
            try writer.count32(header.screenshotWidth, "screenshot width")
            try writer.count32(header.screenshotHeight, "screenshot height")
            writer.uint16(header.compression.rawValue)
        }
    }

    private func screenshotData() throws(ESSError) -> Data {
        let side = 0 ... ESSHeader.maximumScreenshotSide
        let width = header.screenshotWidth
        let height = header.screenshotHeight
        guard
            side.contains(width), side.contains(height),
            screenshot.width == width, screenshot.height == height,
            screenshot.rgba.count == width * height * 4
        else {
            throw .invalidValue(context: "screenshot does not match \(width)x\(height) RGBA")
        }
        return screenshot.rgba
    }
}

/// The body: everything after the screenshot, before compression.
nonisolated extension ESSFileContents {
    /// Size of the location table: ten words and fifteen unused ones.
    static let locationTableSize = 25 * 4

    /// `bodyStart` is the file offset of the body in an uncompressed file, which the
    /// location table's offsets count from.
    func bodyData(bodyStart: Int) throws(ESSError) -> Data {
        let pluginInfo = try pluginData()
        let sections = try [
            Self.tableData(globalData1), Self.tableData(globalData2), changeFormData(),
            Self.tableData(globalData3), idArrayData(), Data(count: 4)
        ]
        var offsets: [Int] = []
        var position = bodyStart + 1 + 4 + pluginInfo.count + Self.locationTableSize
        for section in sections {
            offsets.append(position)
            position += section.count
        }
        var writer = ESSWriter()
        writer.uint8(formVersion)
        try writer.count32(pluginInfo.count, "plugin info size")
        writer.bytes(pluginInfo)
        // Table order: form id array, unknown table 3, then the four sections in order.
        for index in [4, 5, 0, 1, 2, 3] {
            try writer.count32(offsets[index], "file location table offset")
        }
        try writer.count32(globalData1.count, "global data table 1 count")
        try writer.count32(globalData2.count, "global data table 2 count")
        // The game writes one less than the tables present (docs/formats/ess.md).
        try writer.count32(max(0, globalData3.count - 1), "global data table 3 count")
        try writer.count32(changeForms.count, "change form count")
        writer.bytes(Data(count: 15 * 4))
        sections.forEach { writer.bytes($0) }
        return writer.data
    }

    private func pluginData() throws(ESSError) -> Data {
        try ESSWriter.build { writer throws(ESSError) in
            guard plugins.count <= Int(UInt8.max) else {
                throw .invalidCount(context: "plugin list", count: plugins.count)
            }
            writer.uint8(UInt8(plugins.count))
            for name in plugins {
                try writer.wstring(name, "plugin name")
            }
            guard formVersion >= ESSFile.firstLightPluginFormVersion else {
                guard lightPlugins.isEmpty else {
                    throw .invalidValue(context: "light plugins need form version 78")
                }
                return
            }
            guard lightPlugins.count <= Int(UInt16.max) else {
                throw .invalidCount(context: "light plugin list", count: lightPlugins.count)
            }
            writer.uint16(UInt16(lightPlugins.count))
            for name in lightPlugins {
                try writer.wstring(name, "light plugin name")
            }
        }
    }

    private static func tableData(_ tables: [ESSGlobalData]) throws(ESSError) -> Data {
        try ESSWriter.build { writer throws(ESSError) in
            for table in tables {
                writer.uint32(table.type)
                try writer.count32(table.data.count, "global data length")
                writer.bytes(table.data)
            }
        }
    }

    private func changeFormData() throws(ESSError) -> Data {
        try ESSWriter.build { writer throws(ESSError) in
            for form in changeForms {
                try form.write(into: &writer)
            }
        }
    }

    private func idArrayData() throws(ESSError) -> Data {
        try ESSWriter.build { writer throws(ESSError) in
            try writer.count32(formIDArray.count, "form id array")
            formIDArray.forEach { writer.uint32($0) }
            try writer.count32(visitedWorldspaces.count, "visited worldspaces")
            visitedWorldspaces.forEach { writer.uint32($0) }
        }
    }
}
