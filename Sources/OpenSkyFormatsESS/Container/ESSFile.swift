// A whole `.ess`: header, screenshot, and the body after decompression. Sections are
// read where the file location table says they start, after each offset is checked
// against the body. See docs/formats/ess.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ESSFile: Equatable, Sendable {
    public let header: ESSHeader
    public let screenshot: ESSScreenshot
    public let formVersion: UInt8
    /// Full plugins, in the save's load order.
    public let plugins: [String]
    /// Light plugins, in their own order. Empty before form version 78.
    public let lightPlugins: [String]
    public let locationTable: ESSFileLocationTable
    public let globalData1: [ESSGlobalData]
    public let globalData2: [ESSGlobalData]
    public let globalData3: [ESSGlobalData]
    public let changeForms: [ESSChangeForm]
    /// Runtime form ids that a `formIDArray` ref id indexes, one past the index.
    public let formIDArray: [UInt32]
    public let visitedWorldspaces: [UInt32]
    /// Length of the decompressed body, which the section ranges were checked against.
    public let bodyLength: Int
    /// What the location table's offsets count from, derived from where the first
    /// global table really starts. `expectedOffsetBase` is the file offset of the body;
    /// the docs page records whether real saves agree.
    public let offsetBase: Int
    public let expectedOffsetBase: Int

    /// Form versions this build reads. 74 is Special Edition 1.5.97; 78 adds light
    /// plugins. Earlier ones are Legendary Edition.
    public static let supportedFormVersions: ClosedRange<UInt8> = 57 ... 79
    public static let firstLightPluginFormVersion: UInt8 = 78
    /// Sanity cap on a decompressed body.
    public static let maximumBodyLength = 1 << 30

    public init(data: Data) throws(ESSError) {
        let summary = try ESSSummary(data: data)
        header = summary.header
        screenshot = summary.screenshot
        let body = try Self.body(of: data, summary: summary)
        bodyLength = body.data.count
        var reader = ESSReader(body.data)
        formVersion = try reader.uint8("form version")
        guard Self.supportedFormVersions.contains(formVersion) else {
            throw .unsupportedFormVersion(formVersion)
        }
        _ = try reader.uint32("plugin info size")
        plugins = try Self.readPlugins(&reader, countWidth: 1, "plugin")
        lightPlugins = header.isSpecialEdition && formVersion >= Self.firstLightPluginFormVersion
            ? try Self.readPlugins(&reader, countWidth: 2, "light plugin") : []
        let table = try ESSFileLocationTable(&reader)
        let sections = try table.sections(tableEnd: reader.offset, bodyLength: body.data.count)
        locationTable = table
        offsetBase = sections.base
        expectedOffsetBase = body.base
        reader.seek(to: sections.globalData1)
        globalData1 = try ESSGlobalData.read(&reader, count: Int(table.counts.globalData1))
        reader.seek(to: sections.globalData2)
        globalData2 = try ESSGlobalData.read(&reader, count: Int(table.counts.globalData2))
        reader.seek(to: sections.changeForms)
        changeForms = try ESSChangeForm.read(&reader, count: Int(table.counts.changeForms))
        reader.seek(to: sections.globalData3)
        globalData3 = try ESSGlobalData.read(&reader, until: sections.formIDArray)
        reader.seek(to: sections.formIDArray)
        formIDArray = try Self.readFormIDs(&reader, "form id array")
        visitedWorldspaces = try Self.readFormIDs(&reader, "visited worldspaces")
    }

    /// Every global data table, all three groups in file order.
    public var globalData: [ESSGlobalData] {
        globalData1 + globalData2 + globalData3
    }

    public func globalData(_ type: ESSGlobalDataType) -> ESSGlobalData? {
        globalData.first { $0.type == type.rawValue }
    }

    /// The bytes after the screenshot, decompressed. `base` is the file offset the
    /// location table counts from for those bytes.
    private static func body(
        of data: Data, summary: ESSSummary
    ) throws(ESSError) -> (data: Data, base: Int) {
        var reader = ESSReader(data)
        reader.seek(to: summary.bodyOffset)
        guard summary.header.compression != .none else {
            return try (reader.bytes(reader.bytesRemaining, "body"), summary.bodyOffset)
        }
        let uncompressed = try Int(reader.uint32("uncompressed length"))
        let compressed = try Int(reader.uint32("compressed length"))
        guard uncompressed <= maximumBodyLength else {
            throw .invalidCount(context: "uncompressed length", count: uncompressed)
        }
        let packed = try reader.bytes(compressed, "compressed body")
        do {
            let unpacked = switch summary.header.compression {
            case .lz4: try LZ4.decompressRawBlock(packed, decompressedSize: uncompressed)
            case .zlib, .none: try Zlib.decompress(packed, decompressedSize: uncompressed)
            }
            return (unpacked, summary.bodyOffset + 8)
        } catch {
            throw .decompressionFailed(
                context: "\(summary.header.compression.name) body: \(error)"
            )
        }
    }

    private static func readPlugins(
        _ reader: inout ESSReader, countWidth: Int, _ context: String
    ) throws(ESSError) -> [String] {
        let count = countWidth == 1
            ? try Int(reader.uint8("\(context) count"))
            : try Int(reader.uint16("\(context) count"))
        guard count * 2 <= reader.bytesRemaining else {
            throw .invalidCount(context: "\(context) list", count: count)
        }
        var names: [String] = []
        names.reserveCapacity(count)
        for _ in 0 ..< count {
            try names.append(reader.wstring("\(context) name"))
        }
        return names
    }

    private static func readFormIDs(
        _ reader: inout ESSReader, _ context: String
    ) throws(ESSError) -> [UInt32] {
        let count = try reader.count32(context, minimumElementSize: 4)
        var ids: [UInt32] = []
        ids.reserveCapacity(count)
        for _ in 0 ..< count {
            try ids.append(reader.uint32(context))
        }
        return ids
    }
}
