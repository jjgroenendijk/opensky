// Text planning for the SWF layer, re-run per update without rebuilding the package.
// Stateful, so a font keeps the same atlas key across updates and glyphs are not
// rasterized twice.

import Foundation
import OpenSkyFormatsSWF
import simd

nonisolated public final class SWFTextPlanner {
    public let scene: SWFMovieScene
    /// Movie generation, which namespaces this movie's atlas keys.
    public let generation: Int

    /// Texts that could not be planned in the most recent pass (unresolved
    /// font, or a font with no glyphs).
    public private(set) var skipped = 0
    private var externalFontKeys: [String: Int] = [:]

    public init(scene: SWFMovieScene, generation: Int) {
        self.scene = scene
        self.generation = generation
    }

    /// Plans every text draw of a command stream, keyed by command index.
    /// Resets `skipped` so the count always describes the newest stream.
    public func plan(commands: [SWFSceneCommand]) -> [Int: [SWFMovieResources.PlannedTextRun]] {
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

    /// Bit position of the movie generation inside an atlas font key.
    public static let generationShift = 18

    /// The movie generation an atlas font key belongs to, so a released movie's glyphs
    /// can be evicted.
    public static func generation(forFontKey key: Int) -> Int {
        key >> generationShift
    }

    /// Atlas key namespace: bits 0-15 the internal font id, bit 17 the
    /// external-substitution flag, bits 18+ the movie generation. Unique per
    /// (loaded movie, font) as the shared atlas cache requires.
    private func internalFontKey(_ fontID: UInt16) -> Int {
        (generation << Self.generationShift) | Int(fontID)
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
        let key = (generation << Self.generationShift) | 0x20000 | externalFontKeys.count
        externalFontKeys[name] = key
        return key
    }

    public static func straightColor(_ color: SWFColor) -> SIMD4<Float> {
        SIMD4(
            Float(color.red) / 255,
            Float(color.green) / 255,
            Float(color.blue) / 255,
            Float(color.alpha) / 255
        )
    }
}
