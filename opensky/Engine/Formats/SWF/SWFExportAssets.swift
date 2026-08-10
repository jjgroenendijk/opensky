// ExportAssets (56): the linkage table. A movie exports characters under
// names, and those names are what `Object.registerClass(linkageName, class)`
// binds a class to and what `MovieClip.attachMovie(linkageName, ...)` looks up.
// Without this table a registered class has no character to attach to, so
// nothing the ActionScript registers can ever be instantiated.
//
// The mirror image is ImportAssets/ImportAssets2 (57/71), which name characters
// borrowed from another movie — see `SWFImportAssets.swift`.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 14
// "Sharing fonts and other assets" — "ExportAssets", the tag immediately
// preceding ImportAssets. Layout:
//   Count UI16, Count x (CharacterId UI16, Name STRING)
// which is ImportAssets' body without the leading URL.

import Foundation

/// One exported character: the id inside this movie plus the linkage name
/// other movies and ActionScript address it by.
nonisolated struct SWFExportedAsset: Equatable {
    let characterId: UInt16
    let name: String
}

/// One ExportAssets (56) tag.
nonisolated struct SWFExportedAssets: Equatable {
    static let tagCode: UInt16 = 56

    let assets: [SWFExportedAsset]

    static func parse(tag: SWFTag) throws -> SWFExportedAssets {
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
