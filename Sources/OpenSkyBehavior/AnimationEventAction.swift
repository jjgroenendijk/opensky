// What a clip annotation asks the engine to do, beyond the graph itself. The text is
// `<event>` or `<event>.<payload>`, as the census of the install's clips shows.
// See docs/engine/animation-events.md.

import Foundation

nonisolated public enum AnimationEventAction: Equatable, Sendable {
    /// Plays the `SNDR` with this editor ID at the source. `node` names the bone or
    /// node of `SoundPlayAt`; the sound still plays at the source's position.
    case playSound(editorID: String, node: String?)
    /// Ends the loop of this `SNDR` that the same source started.
    case stopSound(editorID: String)
    /// Shakes the camera from the source, with a strength in 0...1.
    case cameraShake(strength: Float)
    /// Lets the source's head turn toward a target again, or holds it forward.
    case headTracking(enabled: Bool)

    /// The annotation names this parser reads, with the payload folded to `.*`, the way
    /// `HKXGapCensus` folds them. Compared without case.
    public static let handledEvents = [
        soundPlay + ".*", soundPlayAt + ".*",
        soundStop + ".*", soundRelease + ".*",
        cameraShake + ".*", headTrackingOn, headTrackingOff
    ]

    static let soundPlay = "SoundPlay"
    static let soundPlayAt = "SoundPlayAt"
    static let soundStop = "SoundStop"
    /// Ends a loop at its next cycle in the game. OpenSky has no release stage, so it stops.
    static let soundRelease = "SoundRelease"
    static let cameraShake = "CameraShake"
    static let headTrackingOn = "HeadTrackingOn"
    static let headTrackingOff = "HeadTrackingOff"

    /// Nil for an annotation the graph or another runtime handles, or an empty payload.
    public static func parse(_ text: String) -> AnimationEventAction? {
        if text.caseInsensitiveCompare(headTrackingOn) == .orderedSame {
            return .headTracking(enabled: true)
        }
        if text.caseInsensitiveCompare(headTrackingOff) == .orderedSame {
            return .headTracking(enabled: false)
        }
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let event = text[..<dot].lowercased()
        let parts = text[text.index(after: dot)...]
            .split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, !first.isEmpty else { return nil }
        switch event {
        case soundPlay.lowercased():
            return .playSound(editorID: first, node: nil)
        case soundPlayAt.lowercased():
            return .playSound(editorID: first, node: parts.count > 1 ? parts[1] : nil)
        case soundStop.lowercased(), soundRelease.lowercased():
            return .stopSound(editorID: first)
        case cameraShake.lowercased():
            return shake(text[text.index(after: dot)...])
        default:
            return nil
        }
    }

    private static func shake(_ payload: Substring) -> AnimationEventAction? {
        guard let strength = Float(payload), strength.isFinite, strength > 0 else { return nil }
        return .cameraShake(strength: min(strength, 1))
    }
}
