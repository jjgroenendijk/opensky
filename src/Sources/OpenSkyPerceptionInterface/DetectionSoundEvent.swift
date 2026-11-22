// See docs/engine/detection-events.md.

/// The last sound event of one actor.
nonisolated public struct DetectionSoundEvent: Equatable, Sendable {
    /// The sound level, 10 for a silent action up to 200 for a very loud one.
    public var level: Float
    public var position: SIMD3<Float>
    /// Seconds since the event.
    public var age: Float = 0

    public init(level: Float, position: SIMD3<Float>) {
        self.level = level
        self.position = position
    }
}
