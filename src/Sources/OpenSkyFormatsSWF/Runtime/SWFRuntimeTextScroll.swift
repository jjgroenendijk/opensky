// `TextField.scroll`, `maxscroll`, and `bottomScroll`. A multiline field that wraps and
// does not size itself shows only the lines that fit its bounds, from `scroll` on.
// See docs/engine/as2-display-runtime.md#text.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// Whether the field shows a window of its lines. GFx `textAutoSize` resizes the text
    /// to fit, and GFx `verticalAutoSize` grows the field to its lines, so a field with
    /// either set draws every line.
    func windowsLines(_ node: SWFDisplayObject) -> Bool {
        TextScrolling(owner: self).windowsLines(node)
    }

    /// The field's box. GFx `verticalAutoSize` fits the height to the laid-out lines plus
    /// the 2-pixel gutter at each edge, keeping the named edge (or the centre) in place, so
    /// `_height` reports a wrapped row's real size and a list can stack its rows.
    func autoSizedBounds(of node: SWFDisplayObject, field: SWFEditText) -> SWFBoundsBox {
        var box = SWFBoundsBox(rect: field.bounds)
        guard
            case let .string(mode) = node.object.lookup("verticalAutoSize")?.property.value
            ?? .undefined,
            ["top", "center", "bottom"].contains(mode),
            let layout = measuredLayout(of: node, characters: false), layout.lineCount > 0
        else {
            return box
        }
        let gutter = 2 * Self.twipsPerPixel
        let height = Float(layout.lineCount - 1) * layout.lineAdvance + layout.lineHeight
            + 2 * gutter
        switch mode {
        case "top":
            box.maxY = box.minY + height
        case "bottom":
            box.minY = box.maxY - height
        default:
            let centre = (box.minY + box.maxY) / 2
            box.minY = centre - height / 2
            box.maxY = centre + height / 2
        }
        return box
    }

    /// An auto-size mode that is unset or "none".
    private func isOff(_ mode: AS2Value?) -> Bool {
        switch mode ?? .undefined {
        case .undefined, .null: true
        case let .string(mode): mode == "none"
        default: false
        }
    }

    /// `scroll`, clamped to `maxscroll` because the text may have shrunk since it was set.
    func textScroll(of node: SWFDisplayObject) -> Int {
        min(max(1, node.textScroll), maxScroll(of: node))
    }

    func scrollMember(_ name: String, of node: SWFDisplayObject) -> AS2Value? {
        guard textField(of: node) != nil else { return nil }
        let scroll = textScroll(of: node)
        switch name {
        case "scroll":
            return .integer(scroll)
        case "maxscroll":
            return .integer(maxScroll(of: node))
        case "numLines":
            return .integer(max(1, measuredLayout(of: node, characters: false)?.lineCount ?? 1))
        default:
            let lines = textLines(of: node)
            let visible = lines.map { min($0.visible, $0.count - scroll + 1) } ?? 1
            return .integer(scroll + max(1, visible) - 1)
        }
    }

    func setTextScroll(_ value: AS2Value, of node: SWFDisplayObject) -> Bool {
        TextScrolling(owner: self).setTextScroll(value, of: node)
    }

    private func maxScroll(of node: SWFDisplayObject) -> Int {
        guard let lines = textLines(of: node) else { return 1 }
        return max(1, lines.count - lines.visible + 1)
    }

    private func textLines(of node: SWFDisplayObject) -> (count: Int, visible: Int)? {
        guard windowsLines(node), let field = textField(of: node) else { return nil }
        return movieScene.lineCounts(of: field, content: text(of: node) ?? "")
    }
}

nonisolated extension SWFMovieScene {
    /// How many lines `content` lays out to in `field`, and how many show at once.
    /// Nil when the field's font does not resolve.
    func lineCounts(of field: SWFEditText, content: String) -> (count: Int, visible: Int)? {
        guard let font = resolvedFont(for: field) else { return nil }
        let layout = SWFTextLayout.editText(field, font: font, content: content, firstLine: 0)
        return (layout.lineCount, layout.visibleLineCount)
    }
}

extension SWFMovieRuntime {
    /// Reads line wrapping and writes the scroll of a text field.
    nonisolated struct TextScrolling {
        let owner: SWFMovieRuntime

        func windowsLines(_ node: SWFDisplayObject) -> Bool {
            guard
                let field = owner.textField(of: node), field.flags.multiline, field.flags.wordWrap,
                !field.flags.autoSize
            else {
                return false
            }
            return owner.isOff(node.object.lookup("textAutoSize")?.property.value)
                && owner.isOff(node.object.lookup("verticalAutoSize")?.property.value)
        }

        func setTextScroll(_ value: AS2Value, of node: SWFDisplayObject) -> Bool {
            let runtime = owner.runtime
            guard owner.textField(of: node) != nil else { return false }
            let number = runtime.coercion.toNumber(value)
            guard number.isFinite else { return true }
            let shown = owner.textScroll(of: node)
            node.textScroll = min(max(1, Int(number)), owner.maxScroll(of: node))
            owner.markDirty()
            if node.textScroll != shown {
                // CLIK's `ScrollBar` listens to its target field for `onScroller`.
                owner.broadcast("onScroller", from: node.object, arguments: [.object(node.object)])
            }
            return true
        }
    }
}
