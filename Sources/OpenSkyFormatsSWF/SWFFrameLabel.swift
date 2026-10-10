// FrameLabel (43): names its frame, so `gotoAndStop("label")` and
// `ActionGoToLabel` have targets. The NamedAnchor byte exists only when the tag
// has a byte left. Layout: docs/formats/swf-display-list.md.

import Foundation
import OpenSkyFormatsCore

/// A decoded FrameLabel (43) tag.
nonisolated public struct SWFFrameLabel: Equatable, Sendable {
    public static let tagCode: UInt16 = 43

    /// The label as authored. Empty when the tag carried no name.
    public let name: String
    /// `NamedAnchor` was present and set — an anchor a browser can seek to.
    /// Recorded for completeness; OpenSky does not navigate to anchors.
    public let isNamedAnchor: Bool

    public static func parse(tag: SWFTag) throws -> SWFFrameLabel {
        guard tag.code == tagCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var reader = BinaryReader(tag.body)
        let name = try reader.readZString()
        let anchor = reader.bytesRemaining > 0 ? try reader.readUInt8() : 0
        return SWFFrameLabel(name: name, isNamedAnchor: anchor == 1)
    }
}
