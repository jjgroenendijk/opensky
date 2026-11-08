public import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// A light the Light archetype placed: on an actor while its effect runs, or at the
/// point an aimed light landed until its duration ends.
nonisolated public struct MagicLight: Equatable, Sendable {
    public enum Anchor: Equatable, Sendable {
        case actor(ReferenceKey)
        case point(SIMD3<Float>)
    }

    /// The `LIGH`.
    public let light: ReferenceKey
    public let anchor: Anchor
    /// The stored effect that holds an actor's light; zero for a point light.
    public let sequence: UInt64
    /// Seconds a point light has left. Nil while an effect holds the light.
    public var remaining: Float?

    public init(
        light: ReferenceKey,
        anchor: Anchor,
        sequence: UInt64 = 0,
        remaining: Float? = nil
    ) {
        self.light = light
        self.anchor = anchor
        self.sequence = sequence
        self.remaining = remaining
    }
}
