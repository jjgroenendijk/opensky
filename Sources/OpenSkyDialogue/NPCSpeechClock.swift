// When each speaker, and every speaker together, may next say each kind of line
// (docs/engine/dialogue.md#speech-timers).

import Foundation
import OpenSkyFormatsESM

/// When each speaker may next say each kind of line, in seconds of the caller's clock.
/// A shared slot holds a line back for every speaker, such as the gap after a hello.
nonisolated public struct NPCSpeechClock: Equatable, Sendable {
    private struct Slot: Hashable, Sendable {
        let speaker: ReferenceKey?
        let line: NPCSpeechLine
    }

    private var readyAt: [Slot: Double] = [:]

    public init() {}

    public func isReady(_ line: NPCSpeechLine, speaker: ReferenceKey, now: Double) -> Bool {
        isSharedReady(line, now: now)
            && now >= readyAt[Slot(speaker: speaker, line: line)] ?? -.infinity
    }

    /// Whether the shared slot of `line` has passed, whoever speaks.
    public func isSharedReady(_ line: NPCSpeechLine, now: Double) -> Bool {
        now >= readyAt[Slot(speaker: nil, line: line)] ?? -.infinity
    }

    public mutating func note(
        _ line: NPCSpeechLine, speaker: ReferenceKey, now: Double, wait: Double,
        sharedWait: Double? = nil
    ) {
        readyAt[Slot(speaker: speaker, line: line)] = now + max(0, wait)
        if let sharedWait {
            readyAt[Slot(speaker: nil, line: line)] = now + max(0, sharedWait)
        }
    }

    public mutating func reset() {
        readyAt = [:]
    }
}
