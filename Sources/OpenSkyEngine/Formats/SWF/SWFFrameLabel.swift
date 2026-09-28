// FrameLabel (43): names the frame it appears in, so `gotoAndStop("label")`
// and `ActionGoToLabel` (0x8C) have a target table. Vanilla Interface movies
// carry them in `inventorymenu.swf`, `loadingmenu.swf`, and
// `racesex_menu.swf`.
//
// Reference: Adobe SWF File Format Specification, version 19 — the "FrameLabel"
// control tag. Layout:
//   Name          STRING   null-terminated, the label
//   NamedAnchor   UI8      optional, present only when a byte remains; a value
//                          of 1 marks the label as a named anchor (SWF 6+)
// The named-anchor byte is optional in the sense that the tag length decides
// whether it is there, which is how a SWF 5 movie and a SWF 6 movie both frame.

import Foundation

/// A decoded FrameLabel (43) tag.
nonisolated struct SWFFrameLabel: Equatable {
    static let tagCode: UInt16 = 43

    /// The label as authored. Empty when the tag carried no name.
    let name: String
    /// `NamedAnchor` was present and set — an anchor a browser can seek to.
    /// Recorded for completeness; OpenSky does not navigate to anchors.
    let isNamedAnchor: Bool

    static func parse(tag: SWFTag) throws -> SWFFrameLabel {
        guard tag.code == tagCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var reader = BinaryReader(tag.body)
        let name = try reader.readZString()
        let anchor = reader.bytesRemaining > 0 ? try reader.readUInt8() : 0
        return SWFFrameLabel(name: name, isNamedAnchor: anchor == 1)
    }
}
