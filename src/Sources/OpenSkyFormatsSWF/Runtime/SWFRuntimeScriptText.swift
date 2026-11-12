// Text fields a script makes with `MovieClip.createTextField`. The movie holds no
// DefineEditText for them, so the runtime keeps their definitions, under character ids
// counted down from the top of the `UI16` range. See docs/engine/as2-display-runtime.md#text.

import Foundation

nonisolated extension SWFMovieRuntime {
    /// A DefineEditText from the movie, or one a script made.
    public func editText(_ id: UInt16) -> SWFEditText? {
        movie.editText(id) ?? scriptEditTexts[id]
    }

    /// A text node's field with the node's own box: `_width` resizes one field, not
    /// the character every instance shares.
    public func textField(of node: SWFDisplayObject) -> SWFEditText? {
        guard case let .editText(id) = node.content, let field = editText(id) else { return nil }
        return node.textBounds.map(field.withBounds) ?? field
    }

    /// `createTextField(name, depth, x, y, width, height)`, with `frame` in parent twips. Flash
    /// gives the field a
    /// device font, and OpenSky has none, so the field holds text but draws nothing.
    func createTextField(
        named name: String,
        in parent: SWFDisplayObject,
        depth: UInt16,
        frame: SWFRect
    ) -> SWFDisplayObject {
        let characterId = nextScriptCharacterID()
        scriptEditTexts[characterId] = SWFEditText(
            characterId: characterId,
            bounds: SWFRect(
                xMin: 0, xMax: frame.xMax - frame.xMin,
                yMin: 0, yMax: frame.yMax - frame.yMin
            ),
            flags: SWFEditTextFlags(), fontID: nil, fontClass: nil, fontHeight: nil,
            color: nil, maxLength: nil, layout: nil, variableName: "", initialText: nil
        )
        let created = SWFDisplayObject(content: .editText(characterId))
        created.object.prototype = textFieldPrototype
        created.object.typeOverride = nil
        created.name = name
        created.moveTo(twipsX: frame.xMin, twipsY: frame.yMin)
        parent.addChild(created, atDepth: depth)
        markDirty()
        return created
    }

    private func nextScriptCharacterID() -> UInt16 {
        var id = UInt16.max - UInt16(min(scriptEditTexts.count, Int(UInt16.max)))
        while movie.characters[id] != nil || scriptEditTexts[id] != nil, id > 0 {
            id -= 1
        }
        return id
    }
}
