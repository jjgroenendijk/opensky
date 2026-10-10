// ImportAssets (57) and ImportAssets2 (71): characters borrowed from another
// movie by name. Vanilla movies import their fonts from the fontlib movies, so
// an edit text's FontID often names a character the movie never defines.
// Layout and sources: docs/formats/swf-display-list.md.

import Foundation
import OpenSkyFormatsCore

/// One imported character: the id the importing movie uses, plus the export
/// name it has in the source movie.
nonisolated public struct SWFImportedAsset: Equatable, Sendable {
    public let characterId: UInt16
    public let name: String
}

/// One ImportAssets/ImportAssets2 tag: the source movie URL plus its assets.
nonisolated public struct SWFImportedAssets: Equatable, Sendable {
    public static let importAssetsCode: UInt16 = 57
    public static let importAssets2Code: UInt16 = 71
    public static let tagCodes: Set<UInt16> = [importAssetsCode, importAssets2Code]

    public let url: String
    public let assets: [SWFImportedAsset]

    public static func parse(tag: SWFTag) throws -> SWFImportedAssets {
        guard tagCodes.contains(tag.code) else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var reader = BinaryReader(tag.body)
        let url = try readString(&reader)
        if tag.code == importAssets2Code {
            _ = try reader.readUInt8() // Reserved, must be 1
            _ = try reader.readUInt8() // Reserved, must be 0
        }
        let count = try Int(reader.readUInt16())
        var assets: [SWFImportedAsset] = []
        assets.reserveCapacity(min(count, 1024))
        for _ in 0 ..< count {
            let characterId = try reader.readUInt16()
            let name = try readString(&reader)
            assets.append(SWFImportedAsset(characterId: characterId, name: name))
        }
        return SWFImportedAssets(url: url, assets: assets)
    }

    /// Null-terminated STRING. SWF 6 and later declare strings UTF-8, older
    /// movies carry code-page bytes, so this takes the engine-wide `GameText`
    /// policy like every other SWF string read.
    private static func readString(_ reader: inout BinaryReader) throws -> String {
        try reader.readZString()
    }
}
