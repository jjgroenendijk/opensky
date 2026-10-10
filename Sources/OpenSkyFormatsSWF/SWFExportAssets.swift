// ExportAssets (56): characters exported under linkage names, which
// `registerClass` and `attachMovie` use. Imports are in SWFImportAssets.swift.
// Layout and sources: docs/formats/swf-display-list.md.

import Foundation
import OpenSkyFormatsCore

/// One exported character: the id inside this movie plus the linkage name
/// other movies and ActionScript address it by.
nonisolated public struct SWFExportedAsset: Equatable, Sendable {
    public let characterId: UInt16
    public let name: String
}

/// One ExportAssets (56) tag.
nonisolated public struct SWFExportedAssets: Equatable, Sendable {
    public static let tagCode: UInt16 = 56

    public let assets: [SWFExportedAsset]

    public static func parse(tag: SWFTag) throws -> SWFExportedAssets {
        guard tag.code == tagCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var reader = BinaryReader(tag.body)
        let count = try Int(reader.readUInt16())
        var assets: [SWFExportedAsset] = []
        assets.reserveCapacity(min(count, 1024))
        for _ in 0 ..< count {
            let characterId = try reader.readUInt16()
            let name = try readString(&reader)
            assets.append(SWFExportedAsset(characterId: characterId, name: name))
        }
        return SWFExportedAssets(assets: assets)
    }

    /// Null-terminated STRING. SWF 6 and later declare strings UTF-8, older
    /// movies carry code-page bytes, so this takes the engine-wide `GameText`
    /// policy like every other SWF string read.
    private static func readString(_ reader: inout BinaryReader) throws -> String {
        try reader.readZString()
    }
}
