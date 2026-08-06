// Renderer-facing movie package: a decoded movie plus the fonts resolved from
// outside it. Vanilla movies define placeholder fonts named after fontconfig
// aliases ("$EverywhereFont", ...) with zero glyphs; the real outlines live in
// the fontlib movies (fonts_en.swf, ...), so an edit text renders through the
// external font its placeholder name (or its FontClass) resolves to.
// Resolution through fontconfig is observed GFx behavior — see
// docs/formats/swf.md "fontconfig.txt".

import Foundation

/// What the renderer draws: the movie plus its external font substitutions.
nonisolated struct SWFMovieScene {
    let movie: SWFMovie
    /// Fonts substituted by name: keys are the placeholder font name or the
    /// edit text's FontClass (exact match first, then lowercased).
    var externalFonts: [String: SWFFontDefinition] = [:]
    /// Font names/classes that could not be resolved anywhere (tally).
    var unresolvedFontNames: [String] = []

    /// The font an edit text renders with: its own movie font when that font
    /// has glyphs, otherwise the external substitution registered for the
    /// placeholder's name or the field's FontClass. nil -> the text is
    /// skipped (counted by the renderer).
    func resolvedFont(for text: SWFEditText) -> SWFFontDefinition? {
        if let fontID = text.fontID, let internalFont = movie.font(fontID) {
            if !internalFont.glyphs.isEmpty {
                return internalFont
            }
            if let substituted = externalFont(named: internalFont.name) {
                return substituted
            }
        }
        // Most vanilla fields point at a FontID the movie only imports
        // (ImportAssets2), so the export name is the thing to resolve.
        if
            let fontID = text.fontID, let imported = movie.importedNames[fontID],
            let substituted = externalFont(named: imported)
        {
            return substituted
        }
        if let fontClass = text.fontClass, let substituted = externalFont(named: fontClass) {
            return substituted
        }
        return nil
    }

    private func externalFont(named name: String) -> SWFFontDefinition? {
        externalFonts[name] ?? externalFonts[name.lowercased()]
    }

    /// Every font name an edit text may need substituted: placeholder
    /// (zero-glyph) internal fonts referenced by FontID, imported FontIDs
    /// (ImportAssets2 export names), plus FontClass names.
    var referencedExternalFontNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for id in movie.characters.keys.sorted() {
            guard case let .editText(text) = movie.characters[id] else { continue }
            if
                let fontID = text.fontID, let font = movie.font(fontID),
                font.glyphs.isEmpty, seen.insert(font.name).inserted
            {
                names.append(font.name)
            }
            if
                let fontID = text.fontID, movie.font(fontID) == nil,
                let imported = movie.importedNames[fontID], seen.insert(imported).inserted
            {
                names.append(imported)
            }
            if let fontClass = text.fontClass, seen.insert(fontClass).inserted {
                names.append(fontClass)
            }
        }
        return names
    }

    /// Resolves every referenced external font name through fontconfig: the
    /// name is looked up as a `map` alias first (the vanilla pattern), then
    /// directly as a registered font name. Unresolved names are recorded, not
    /// fatal — the affected texts fall out with a renderer tally.
    mutating func resolveExternalFonts(config: SWFFontConfig, library: SWFFontLibrary) {
        for name in referencedExternalFontNames {
            let resolved = library.resolve(alias: name, config: config)
                ?? library.font(named: name)
            if let resolved {
                externalFonts[name] = resolved.font
            } else {
                unresolvedFontNames.append(name)
            }
        }
    }
}
