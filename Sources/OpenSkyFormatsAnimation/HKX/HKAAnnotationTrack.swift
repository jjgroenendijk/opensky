// `hkaAnimation::m_annotationTracks` decode: a time plus a text tag that the
// runtime turns into an event. Footstep tags (`FootLeft`, `FootRight`) live
// only here, in the animation file; the behavior graph's clip triggers are
// empty for locomotion. Vanilla fills only the first track, so consumers merge
// the tracks. Byte map: docs/formats/hka-animation.md.

import Foundation

/// One annotation: when it fires inside the clip, and what it is called.
nonisolated public struct HKAAnnotation: Equatable, Sendable {
    /// Seconds from the start of the animation.
    public let time: Float
    public let text: String
}

/// One `hkaAnnotationTrack`: a name and the annotations on it.
nonisolated public struct HKAAnnotationTrack: Equatable, Sendable {
    public let name: String?
    public let annotations: [HKAAnnotation]

    /// `hkaAnnotationTrack`: `m_trackName` then the `m_annotations` hkArray.
    public static let stride = 24
    private static let nameField = HKXField(0x00, "m_trackName")
    private static let annotationsField = HKXField(0x08, "m_annotations")

    /// `hkaAnnotationTrack::Annotation`: a float and a string pointer, the
    /// pointer aligned to 8 so four bytes of padding sit between them.
    private static let annotationStride = 16
    private static let timeField = HKXField(0x00, "m_time")
    private static let textField = HKXField(0x08, "m_text")

    /// `hkaAnimation::m_annotationTracks`, whose offset the animation byte map
    /// records.
    public static let tracksField = HKXField(0x28, "m_annotationTracks")

    /// Reads every annotation track of the `hkaAnimation` `cursor` is open on.
    /// Never throws: an unreadable element is skipped and recorded as a cursor
    /// miss, because a clip without annotations still poses bones.
    public static func tracks(cursor: inout HKXObjectCursor) -> [HKAAnnotationTrack] {
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
