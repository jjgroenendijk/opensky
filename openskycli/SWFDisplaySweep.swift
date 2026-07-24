// Display-list portion of `swf sweep` (milestone 8.2.4 gate): assembles the
// frame-1 display list of every vanilla Interface movie (PlaceObject/2/3,
// RemoveObject/2, ShowFrame, SetBackgroundColor, DefineSprite), flattens it
// into the renderer's draw-command stream, and lays out every edit text with
// the font fontconfig resolves for it. Any movie that fails to decode fails
// the sweep; recorded-but-unrendered features (filters, blend modes,
// ClipActions) are tallied so the deferral stays measured.

import Foundation
import simd

/// Accumulates display-list decode + scene-flattening results across a sweep.
struct SWFDisplayTally {
    var movies = 0
    var moviesWithEmptyFrame1 = 0
    var backgroundColors = 0
    /// Tag-level counters summed over every movie (main timeline + sprites).
    var tags = SWFMovieTally()
    var frame1Placements = 0
    var shapeDraws = 0
    var staticTextDraws = 0
    var editTextDraws = 0
    var clipRanges = 0
    var transparentDraws = 0
    var sceneSkipped = 0
    var editTextGlyphs = 0
    var missingGlyphs = 0
    var editTextsWithoutContent = 0
    var editTextsWithoutFont = 0
    var editTextsWithoutFontReference = 0
    var editTextsWithUnknownFontID = 0
    var unresolvedFontNames = 0
    var failures: [(String, String)] = []

    /// Decodes one movie's display list. `fonts` is the shared fontconfig
    /// environment so edit-text layout matches what the renderer would do.
    mutating func record(
        _ file: SWFFile,
        path: String,
        fonts: SWFMovieLoader.FontEnvironment
    ) {
        do {
            let movie = try SWFMovie(file: file)
            movies += 1
            tags.add(movie.tally)
            frame1Placements += movie.frame1.count
            if movie.frame1.isEmpty {
                moviesWithEmptyFrame1 += 1
            }
            if movie.backgroundColor != nil {
                backgroundColors += 1
            }
            var scene = SWFMovieScene(movie: movie)
            scene.resolveExternalFonts(config: fonts.config, library: fonts.library)
            unresolvedFontNames += scene.unresolvedFontNames.count
            record(scene: SWFScene.build(movie: movie), of: scene)
        } catch {
            failures.append((path, String(describing: error)))
        }
    }

    private mutating func record(scene flattened: SWFScene, of movieScene: SWFMovieScene) {
        sceneSkipped += flattened.skippedPlacements
        for command in flattened.commands {
            switch command {
            case .beginClip:
                clipRanges += 1
            case .endClip:
                continue
            case let .draw(item, _):
                // Vanilla frame 1 hides most content behind a zero-alpha
                // CXFORM and reveals it from ActionScript, so a draw that
                // resolves to alpha 0 is expected, not a defect.
                if item.colorTransform.apply(to: SIMD4(repeating: 1)).w <= 0 {
                    transparentDraws += 1
                }
                switch item.content {
                case .shape: shapeDraws += 1
                case .staticText: staticTextDraws += 1
                case let .editText(characterId):
                    recordEditText(characterId, of: movieScene)
                }
            }
        }
    }

    private mutating func recordEditText(_ characterId: UInt16, of movieScene: SWFMovieScene) {
        editTextDraws += 1
        guard let text = movieScene.movie.editText(characterId) else { return }
        // Empty fields draw nothing regardless of their font, so the renderer
        // never resolves one for them; count them apart from real misses.
        guard text.plainText?.isEmpty == false else {
            editTextsWithoutContent += 1
            return
        }
        guard let font = movieScene.resolvedFont(for: text) else {
            editTextsWithoutFont += 1
            if text.fontID == nil, text.fontClass == nil {
                editTextsWithoutFontReference += 1
            }
            if let fontID = text.fontID, movieScene.movie.font(fontID) == nil {
                editTextsWithUnknownFontID += 1
            }
            return
        }
        let layout = SWFTextLayout.editText(text, font: font)
        editTextGlyphs += layout.runs.reduce(0) { $0 + $1.glyphs.count }
        missingGlyphs += layout.missingGlyphs
    }

    func printReport() {
        print(
            "[INFO] swf sweep display: \(movies) movies "
                + "(\(moviesWithEmptyFrame1) with an empty frame 1), "
                + "\(frame1Placements) frame-1 placements, "
                + "\(backgroundColors) background colors, \(failures.count) failed"
        )
        print(
            "[INFO] swf sweep display tags: PlaceObject \(tags.placeObject), "
                + "PlaceObject2 \(tags.placeObject2), PlaceObject3 \(tags.placeObject3), "
                + "\(tags.moves) moves, \(tags.removals) removals, "
                + "\(tags.showFrames) ShowFrame, \(tags.sprites) sprites, "
                + "\(tags.clipLayers) clip layers"
        )
        print(
            "[INFO] swf sweep display draws: \(shapeDraws) shapes, "
                + "\(staticTextDraws) static texts, \(editTextDraws) edit texts, "
                + "\(clipRanges) clip ranges, \(transparentDraws) fully transparent, "
                + "\(sceneSkipped) undrawable placements"
        )
        print(
            "[INFO] swf sweep display deferred: \(tags.filters) filters, "
                + "\(tags.blendModes) blend modes, \(tags.clipActions) ClipActions, "
                + "\(tags.danglingPlacements) dangling placements"
        )
        print(
            "[INFO] swf sweep display text: \(editTextGlyphs) glyphs laid out, "
                + "\(missingGlyphs) missing glyphs, "
                + "\(editTextsWithoutContent) empty fields, "
                + "\(editTextsWithoutFont) edit texts without a font "
                + "(\(editTextsWithoutFontReference) name no font at all, "
                + "\(editTextsWithUnknownFontID) name a FontID the movie never defines), "
                + "\(unresolvedFontNames) unresolved font names"
        )
    }
}
