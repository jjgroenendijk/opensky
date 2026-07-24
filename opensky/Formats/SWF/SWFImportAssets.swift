// ImportAssets (57) and ImportAssets2 (71): a movie borrows characters from
// another movie by name, so a character id used by its own tags (an edit
// text's FontID, for example) is defined nowhere inside the file. Vanilla
// Skyrim Interface movies import their fonts this way from the fontlib
// movies named in Interface\fontconfig.txt, which is why an edit text's
// FontID frequently names a character the movie never defines.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 14
// "Sharing fonts and other assets" — ImportAssets (p. 285) and ImportAssets2
// (p. 286). Layout:
//   ImportAssets:  URL STRING, Count UI16, Count x (CharacterId UI16, Name STRING)
//   ImportAssets2: URL STRING, Reserved UI8 (1), Reserved UI8 (0),
//                  Count UI16, Count x (CharacterId UI16, Name STRING)
// The two reserved bytes are the only difference between the versions.

import Foundation

/// One imported character: the id the importing movie uses, plus the export
/// name it has in the source movie.
nonisolated struct SWFImportedAsset: Equatable {
    let characterId: UInt16
    let name: String
}

/// One ImportAssets/ImportAssets2 tag: the source movie URL plus its assets.
nonisolated struct SWFImportedAssets: Equatable {
    static let importAssetsCode: UInt16 = 57
    static let importAssets2Code: UInt16 = 71
    static let tagCodes: Set<UInt16> = [importAssetsCode, importAssets2Code]

    let url: String
    let assets: [SWFImportedAsset]

    static func parse(tag: SWFTag) throws -> SWFImportedAssets {
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

    /// Null-terminated STRING: UTF-8 (SWF 6+) with a CP1252 fallback, matching
    /// the other SWF string readers.
    private static func readString(_ reader: inout BinaryReader) throws -> String {
        let bytes = try reader.readZStringData()
        return String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .windowsCP1252) ?? ""
    }
}
