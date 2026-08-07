// `hkaAnimation::m_annotationTracks` decode (issues #385, #394).
//
// An annotation is how an animator marks a moment inside a clip: a time and a
// short piece of text the runtime turns into an event. Skyrim's footstep chain
// is built on them — `mt_walkforward.hkx` carries `FootLeft` and `FootRight`,
// which are the tags the `FSTS` footstep sets answer to — and they live in the
// *animation* file rather than in the behavior file that plays it. Nothing in
// `mt_behavior.hkx` names them: its locomotion `hkbClipGenerator`s carry an
// empty `m_triggers` array, so a runtime that reads only `hkbClipTriggerArray`
// never fires a footstep however long it walks.
//
// Object layout is `hkaAnimation`'s, which
// `HKASplineCompressedAnimation`'s byte map already covers through 0x38:
// `m_annotationTracks` is the hkArray at 0x28. Element layouts below were
// probe-verified against Skyrim SE's `meshes\actors\character\animations\male\
// mt_walkforward.hkx` (hk_2010.2.0-r1, 64-bit LE) on 2026-08-07; member names
// and order come from the same hkxparse (MIT) and HKX2Library (MIT) class
// dumps the animation page cites. Full byte map: docs/formats/hka-animation.md.
//
// One track per transform track is exported, and vanilla leaves all but the
// first empty, so a consumer wants the tracks merged rather than indexed.

import Foundation

/// One annotation: when it fires inside the clip, and what it is called.
nonisolated struct HKAAnnotation: Equatable, Sendable {
    /// Seconds from the start of the animation.
    let time: Float
    let text: String
}

/// One `hkaAnnotationTrack`: a name and the annotations on it.
nonisolated struct HKAAnnotationTrack: Equatable, Sendable {
    let name: String?
    let annotations: [HKAAnnotation]

    /// `hkaAnnotationTrack`: `m_trackName` then the `m_annotations` hkArray.
    static let stride = 24
    private static let nameField = HKXField(0x00, "m_trackName")
    private static let annotationsField = HKXField(0x08, "m_annotations")

    /// `hkaAnnotationTrack::Annotation`: a float and a string pointer, the
    /// pointer aligned to 8 so four bytes of padding sit between them.
    private static let annotationStride = 16
    private static let timeField = HKXField(0x00, "m_time")
    private static let textField = HKXField(0x08, "m_text")

    /// `hkaAnimation::m_annotationTracks`, whose offset the animation byte map
    /// records.
    static let tracksField = HKXField(0x28, "m_annotationTracks")

    /// Reads every annotation track of the `hkaAnimation` `cursor` is open on.
    ///
    /// Never throws and never fails the animation: an animation whose
    /// annotations cannot be read still poses bones, and a clip with no
    /// annotations is the ordinary case. An unreadable element is skipped and
    /// recorded as a cursor miss, in keeping with "unknown field or variant ->
    /// skip and note" (AGENTS.md "Code quality").
    static func tracks(cursor: inout HKXObjectCursor) -> [HKAAnnotationTrack] {
        guard let view = cursor.array(at: tracksField) else { return [] }
        var tracks: [HKAAnnotationTrack] = []
        tracks.reserveCapacity(view.count)
        for index in 0 ..< view.count {
            guard
                var element = cursor.graph.element(of: view, index: index, stride: stride)
            else {
                cursor.recordMiss(tracksField, .outOfBounds)
                continue
            }
            let name = element.string(at: nameField)
            let annotations = readAnnotations(cursor: &element)
            cursor.absorb(element)
            tracks.append(HKAAnnotationTrack(name: name, annotations: annotations))
        }
        return tracks
    }

    /// The annotations of one track, in file order.
    private static func readAnnotations(cursor: inout HKXObjectCursor) -> [HKAAnnotation] {
        guard let view = cursor.array(at: annotationsField) else { return [] }
        var annotations: [HKAAnnotation] = []
        annotations.reserveCapacity(view.count)
        for index in 0 ..< view.count {
            guard
                var element = cursor.graph.element(
                    of: view, index: index, stride: annotationStride
                )
            else {
                cursor.recordMiss(annotationsField, .outOfBounds)
                continue
            }
            let time = element.float32(at: timeField)
            let text = element.string(at: textField)
            cursor.absorb(element)
            // A nameless annotation names no event and a non-finite time never
            // lies inside a clip window, so neither could ever fire.
            guard let time, time.isFinite, let text, !text.isEmpty else { continue }
            annotations.append(HKAAnnotation(time: time, text: text))
        }
        return annotations
    }
}
