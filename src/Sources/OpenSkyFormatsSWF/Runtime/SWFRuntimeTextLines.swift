// `TextField.getLineOffset`, `getCharBoundaries`, and `getLineMetrics`, which a movie uses
// to place a clip next to its text: the journal places its objectives under the quest
// description, and its bottom bar buttons after their labels. All read the field's layout.
// See docs/engine/as2-display-runtime.md#text.

import Foundation

nonisolated extension SWFMovieRuntime {
    static func installTextFieldLines(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Runtime.method(runtime, on: prototype, name: "getLineOffset") { context in
            guard
                let owner = movieRuntime(context), let node = node(context),
                let layout = owner.measuredLayout(of: node, characters: false)
            else { return .integer(-1) }
            let line = try context.number(0)
            guard line.isFinite, line >= 0, Int(line) < layout.lineStarts.count else {
                return .integer(-1)
            }
            return .integer(layout.lineStarts[Int(line)])
        }
        AS2Runtime.method(runtime, on: prototype, name: "getCharBoundaries") { context in
            guard
                let owner = movieRuntime(context), let node = node(context),
                let layout = owner.measuredLayout(of: node, characters: true)
            else { return .undefined }
            let character = try context.number(0)
            guard
                character.isFinite,
                let box = layout.characterBoxes.first(where: { $0.character == Int(character) })
            else { return .undefined }
            let firstLine = owner.windowsLines(node) ? owner.textScroll(of: node) - 1 : 0
            let top = Float(box.line - firstLine) * layout.lineAdvance
            let frame = RectangleBox(
                x: Double(box.x / 20), y: Double(top / 20),
                width: Double(box.width / 20), height: Double(layout.lineHeight / 20)
            )
            return makeRectangle(context.runtime, frame)
        }
        installTextFieldLineMetrics(runtime, prototype: prototype)
    }

    static func installTextFieldLineMetrics(_ runtime: AS2Runtime, prototype: AS2Object) {
        AS2Runtime.method(runtime, on: prototype, name: "getLineMetrics") { context in
            guard
                let owner = movieRuntime(context), let node = node(context),
                let layout = owner.measuredLayout(of: node, characters: true)
            else { return .undefined }
            let line = try context.number(0)
            guard line.isFinite, line >= 0, Int(line) < max(1, layout.lineStarts.count) else {
                return .undefined
            }
            let boxes = layout.characterBoxes.filter { $0.line == Int(line) }
            let left = boxes.map(\.x).min() ?? 0
            let right = boxes.map { $0.x + $0.width }.max() ?? left
            let metrics = context.runtime.makeObject()
            let values: [(String, Float)] = [
                ("x", left), ("width", right - left), ("height", layout.lineAdvance),
                ("ascent", layout.ascent), ("descent", layout.lineHeight - layout.ascent),
                ("leading", layout.lineAdvance - layout.lineHeight)
            ]
            for (name, twips) in values {
                metrics.assign(.number(Double(twips / 20)), for: name)
            }
            return .object(metrics)
        }
    }

    /// The field's text laid out from its first line, or nil when its font does not resolve.
    func measuredLayout(of node: SWFDisplayObject, characters: Bool) -> SWFTextLayoutResult? {
        guard let field = textField(of: node), let font = movieScene.resolvedFont(for: field) else {
            return nil
        }
        return SWFTextLayout.editText(
            field, font: font, content: text(of: node) ?? "", images: textImages(of: node),
            styles: textStyles(of: node), measuresCharacters: characters
        )
    }
}
