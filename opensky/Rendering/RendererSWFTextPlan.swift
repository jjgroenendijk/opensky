// Text planning for the SWF layer, split out of the movie build (M8.3.2) so a
// dynamic command stream can be re-planned per update without rebuilding
// tessellation, textures, or the glyph atlas.
//
// The planner is stateful on purpose: glyph-atlas font keys must stay stable
// across updates, or every re-plan would re-rasterize the same glyphs under new
// keys and the shared atlas would fill with duplicates. Keeping the
// external-font key table on the planner keys a font to the same slot for the
// whole life of the movie package.

import Foundation
import simd

nonisolated final class SWFTextPlanner {
    let scene: SWFMovieScene
    /// Movie generation, which namespaces this movie's atlas keys.
    let generation: Int

    /// Texts that could not be planned in the most recent pass (unresolved
    /// font, or a font with no glyphs).
    private(set) var skipped = 0
    private var externalFontKeys: [String: Int] = [:]

    init(scene: SWFMovieScene, generation: Int) {
        self.scene = scene
        self.generation = generation
    }

    /// Plans every text draw of a command stream, keyed by command index.
    /// Resets `skipped` so the count always describes the newest stream.
    func plan(commands: [SWFSceneCommand]) -> [Int: [SWFMovieResources.PlannedTextRun]] {
        skipped = 0
        var plans: [Int: [SWFMovieResources.PlannedTextRun]] = [:]
        for (index, command) in commands.enumerated() {
            guard case let .draw(item, _) = command else { continue }
            switch item.content {
            case .shape:
                continue
            case let .staticText(id):
                guard let text = scene.movie.staticText(id) else { continue }
                plans[index] = planStaticText(text)
            case let .editText(id):
                guard let text = scene.movie.editText(id) else { continue }
                plans[index] = planEditText(text, content: item.textOverride)
            }
        }
        return plans
    }

    private func planStaticText(_ text: SWFTextDefinition)
        -> [SWFMovieResources.PlannedTextRun]
    {
        var planned: [SWFMovieResources.PlannedTextRun] = []
        for run in SWFTextLayout.staticText(text).runs {
            guard
                let fontID = run.fontID, let font = scene.movie.font(fontID),
                !font.glyphs.isEmpty
            else {
                skipped += 1
                continue
            }
            planned.append(SWFMovieResources.PlannedTextRun(
                font: font,
                fontKey: internalFontKey(fontID),
                emTwips: run.emTwips,
                color: SWFTextPlanner.straightColor(run.color),
                glyphs: run.glyphs
            ))
        }
        return planned
    }

    /// `content` is the runtime string an `SWFSceneItem` carried; nil keeps the
    /// character's authored `InitialText`.
    private func planEditText(_ text: SWFEditText, content: String?)
        -> [SWFMovieResources.PlannedTextRun]
    {
        let resolved = content ?? text.plainText
        guard resolved?.isEmpty == false else { return [] }
        guard let font = scene.resolvedFont(for: text) else {
            skipped += 1
            return []
        }
        let layout = SWFTextLayout.editText(text, font: font, content: content)
        return layout.runs.map { run in
            SWFMovieResources.PlannedTextRun(
                font: font,
                fontKey: fontKey(for: font, editText: text),
                emTwips: run.emTwips,
                color: SWFTextPlanner.straightColor(run.color),
                glyphs: run.glyphs
            )
        }
    }

    /// Atlas key namespace: bits 0-15 the internal font id, bit 17 the
    /// external-substitution flag, bits 18+ the movie generation. Unique per
    /// (loaded movie, font) as the shared atlas cache requires.
    private func internalFontKey(_ fontID: UInt16) -> Int {
        (generation << 18) | Int(fontID)
    }

    private func fontKey(for font: SWFFontDefinition, editText: SWFEditText) -> Int {
        if
            let fontID = editText.fontID, let internalFont = scene.movie.font(fontID),
            !internalFont.glyphs.isEmpty
        {
            return internalFontKey(fontID)
        }
        let name = font.name
        if let existing = externalFontKeys[name] {
            return existing
        }
        let key = (generation << 18) | 0x20000 | externalFontKeys.count
        externalFontKeys[name] = key
        return key
    }

    static func straightColor(_ color: SWFColor) -> SIMD4<Float> {
        SIMD4(
            Float(color.red) / 255,
            Float(color.green) / 255,
            Float(color.blue) / 255,
            Float(color.alpha) / 255
        )
    }
}
