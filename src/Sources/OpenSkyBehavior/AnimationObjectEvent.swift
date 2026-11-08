// A clip annotation that loads or shows an animation object (`ANIO`), such as
// `AnimObjDraw.AnimObjectSkeletonKey`. The object's own `BNAM` event takes it off.
// See docs/engine/animation-events.md.

import Foundation

nonisolated public enum AnimationObjectEvent: Equatable, Sendable {
    /// Readies the `ANIO` with this editor ID. OpenSky loads the model at the draw.
    case load(editorID: String)
    /// Shows the `ANIO` with this editor ID on the actor that plays the clip.
    case draw(editorID: String)

    /// The annotation names this parser reads, folded the way `HKXGapCensus` folds them.
    public static let handledEvents = [load + ".*", draw + ".*"]

    static let load = "AnimObjLoad"
    static let draw = "AnimObjDraw"

    /// Nil for any other annotation, or an empty editor ID.
    public static func parse(_ text: String) -> AnimationObjectEvent? {
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let editorID = String(text[text.index(after: dot)...])
        guard !editorID.isEmpty else { return nil }
        let event = text[..<dot]
        if event.caseInsensitiveCompare(load) == .orderedSame {
            return .load(editorID: editorID)
        }
        if event.caseInsensitiveCompare(draw) == .orderedSame {
            return .draw(editorID: editorID)
        }
        return nil
    }

    /// The editor IDs the annotations name, each once, in first-seen order.
    public static func editorIDs(in texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts.compactMap(parse).compactMap { event in
            let editorID = switch event {
            case let .load(editorID), let .draw(editorID): editorID
            }
            return seen.insert(editorID.lowercased()).inserted ? editorID : nil
        }
    }
}
