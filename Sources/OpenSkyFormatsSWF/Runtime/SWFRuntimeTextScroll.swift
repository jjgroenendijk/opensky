// `TextField.scroll`, `maxscroll`, and `bottomScroll`. A multiline field that wraps and
// does not size itself shows only the lines that fit its bounds, from `scroll` on.
// See docs/engine/as2-display-runtime.md#text.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Whether the field shows a window of its lines. GFx `textAutoSize` resizes the text
    /// to fit instead, so a field with it set draws every line.
    public func windowsLines(_ node: SWFDisplayObject) -> Bool {
        guard
            let field = editTextField(of: node), field.flags.multiline, field.flags.wordWrap,
            !field.flags.autoSize
        else {
            return false
        }
        switch node.object.lookup("textAutoSize")?.property.value ?? .undefined {
        case .undefined, .null: return true
        case let .string(mode): return mode == "none"
        default: return false
        }
    }

    /// `scroll`, clamped to `maxscroll` because the text may have shrunk since it was set.
    public func textScroll(of node: SWFDisplayObject) -> Int {
        min(max(1, node.textScroll), maxScroll(of: node))
    }

    func scrollMember(_ name: String, of node: SWFDisplayObject) -> AS2Value? {
        guard editTextField(of: node) != nil else { return nil }
        let scroll = textScroll(of: node)
        switch name {
        case "scroll":
            return .integer(scroll)
        case "maxscroll":
            return .integer(maxScroll(of: node))
        default:
            let lines = textLines(of: node)
            let visible = lines.map { min($0.visible, $0.count - scroll + 1) } ?? 1
            return .integer(scroll + max(1, visible) - 1)
        }
    }

    func setTextScroll(_ value: AS2Value, of node: SWFDisplayObject) -> Bool {
        guard editTextField(of: node) != nil else { return false }
        let number = runtime.coercion.toNumber(value)
        guard number.isFinite else { return true }
        node.textScroll = min(max(1, Int(number)), maxScroll(of: node))
        markDirty()
        return true
    }

    private func maxScroll(of node: SWFDisplayObject) -> Int {
        guard let lines = textLines(of: node) else { return 1 }
        return max(1, lines.count - lines.visible + 1)
    }

    private func textLines(of node: SWFDisplayObject) -> (count: Int, visible: Int)? {
        guard
            windowsLines(node), let field = editTextField(of: node),
            let font = movieScene.resolvedFont(for: field)
        else { return nil }
        let layout = SWFTextLayout.editText(
            field, font: font, content: text(of: node) ?? "", firstLine: 0
        )
        return (layout.lineCount, layout.visibleLineCount)
    }

    private func editTextField(of node: SWFDisplayObject) -> SWFEditText? {
        guard case let .editText(id) = node.content else { return nil }
        return movie.editText(id)
    }
}
