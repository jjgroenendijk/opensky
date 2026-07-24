// Resolves a fontconfig alias to a decoded font. A fontlib movie (fonts_en.swf,
// gfxfontlib.swf, ...) is registered by decoding its DefineFont2/3 tags and its
// ExportAssets (56) name table; fonts are then found by name, and an alias is
// resolved through the fontconfig `map` directive that names a font.
//
// GFx font naming is observed, not specified: a `map` font name matches either
// an ExportAssets export name or a DefineFont2/3 internal font name, tried in
// that order and then case-insensitively. Documented in docs/formats/swf.md.

import Foundation

nonisolated struct SWFFontLibrary {
    /// A font found by name, with the movie it came from.
    struct Resolved: Equatable {
        let movie: String
        let font: SWFFontDefinition
    }

    /// Registered fonts in registration order (movie, font).
    private var fonts: [Resolved] = []
    /// Exact-name index (export name or internal name) -> first registered font.
    private var byName: [String: Int] = [:]
    /// Lowercased-name fallback index.
    private var byLowerName: [String: Int] = [:]

    /// Movie file names successfully registered.
    private(set) var registeredMovies: [String] = []

    init() {}

    /// Decodes every DefineFont2/3 in `file` and indexes it by its ExportAssets
    /// export names (if any) and its internal font name. A font that fails to
    /// decode is skipped, not fatal. `movie` is the source file name for
    /// reporting. Returns the number of fonts registered from this movie.
    @discardableResult
    mutating func register(movie: String, file: SWFFile) -> Int {
        registeredMovies.append(movie)
        let exportNames = exportNamesByCharacterId(file)
        var added = 0
        for tag in file.tags where SWFFontDefinition.tagCodes.contains(tag.code) {
            guard let font = try? SWFFontParser.parse(tag: tag) else { continue }
            let index = fonts.count
            fonts.append(Resolved(movie: movie, font: font))
            added += 1
            if let exported = exportNames[font.fontID] {
                indexName(exported, at: index)
            }
            indexName(font.name, at: index)
        }
        return added
    }

    /// The font registered under `name` (exact, then case-insensitive), or nil.
    func font(named name: String) -> Resolved? {
        if let index = byName[name] {
            return fonts[index]
        }
        if let index = byLowerName[name.lowercased()] {
            return fonts[index]
        }
        return nil
    }

    /// Resolves a logical alias (e.g. "$EverywhereFont") to a font: looks up the
    /// alias in the config's `map` directives, then finds a registered font with
    /// that name.
    func resolve(alias: String, config: SWFFontConfig) -> Resolved? {
        guard let map = config.maps.first(where: { $0.alias == alias }) else { return nil }
        return font(named: map.fontName)
    }

    private mutating func indexName(_ name: String, at index: Int) {
        guard !name.isEmpty else { return }
        if byName[name] == nil {
            byName[name] = index
        }
        let lower = name.lowercased()
        if byLowerName[lower] == nil {
            byLowerName[lower] = index
        }
    }

    /// Maps a font character id to its ExportAssets export name. ExportAssets
    /// (tag 56): Count UI16, then Count pairs of (Tag UI16, Name STRING).
    private func exportNamesByCharacterId(_ file: SWFFile) -> [UInt16: String] {
        var names: [UInt16: String] = [:]
        for tag in file.tags where tag.code == 56 {
            guard let pairs = try? decodeExportAssets(tag) else { continue }
            for pair in pairs where names[pair.characterId] == nil {
                names[pair.characterId] = pair.name
            }
        }
        return names
    }

    private struct ExportedAsset {
        let characterId: UInt16
        let name: String
    }

    private func decodeExportAssets(_ tag: SWFTag) throws -> [ExportedAsset] {
        var reader = BinaryReader(tag.body)
        let count = try Int(reader.readUInt16())
        var assets: [ExportedAsset] = []
        assets.reserveCapacity(min(count, 4096))
        for _ in 0 ..< count {
            let characterId = try reader.readUInt16()
            let name = try reader.readZString(encoding: .utf8)
            assets.append(ExportedAsset(characterId: characterId, name: name))
        }
        return assets
    }
}
