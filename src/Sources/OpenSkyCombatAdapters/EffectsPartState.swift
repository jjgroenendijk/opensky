public import Foundation
public import OpenSkyFormatsESM

/// What the parts of `EffectsWorldAdapter` share between frames.
@MainActor
public final class EffectsPartState {
    public var cameraPosition: SIMD3<Float>?
    /// When the impulse step last ran, for the splash timer.
    public var lastImpulseStep: TimeInterval?
    /// The heartbeat's script-sound instance; 0 when none plays.
    public var heartbeatSound: Int32 = 0
    private var spawnedHazards: UInt64 = 0

    public init() {}

    /// The top bit marks effect spawns, so no world-state spawn uses the key.
    private static let effectSpawnBit: UInt64 = 0x8000_0000_0000_0000

    public func nextHazardKey() -> ReferenceKey {
        spawnedHazards += 1
        return .generated(Self.effectSpawnBit | spawnedHazards)
    }
}
