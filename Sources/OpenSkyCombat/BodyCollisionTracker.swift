// Finds loose bodies that hit something: a sudden loss of speed between two steps. The
// sound comes from both materials (docs/engine/impulses.md#collision-sounds).

public import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import simd

nonisolated public struct BodyCollisionTracker: Sendable {
    /// A smaller change is gravity, friction, or a soft roll, and stays silent.
    public static let minimumSpeedLoss: Float = 150
    public static let loudSpeedLoss: Float = 800
    public static let quietestGain: Float = 0.25
    /// Steps a body stays silent after a hit, so a bounce or a slide does not rattle.
    public static let quietSteps = 15

    private var velocities: [ReferenceKey: SIMD3<Float>] = [:]
    private var quiet: [ReferenceKey: Int] = [:]

    public init() {}

    public mutating func update(_ bodies: [ImpulseBody]) -> [BodyCollision] {
        var next: [ReferenceKey: SIMD3<Float>] = [:]
        var hits: [BodyCollision] = []
        for body in bodies {
            next[body.key] = body.velocity
            let steps = quiet[body.key] ?? 0
            quiet[body.key] = steps > 0 ? steps - 1 : nil
            guard steps == 0, let previous = velocities[body.key] else { continue }
            let loss = simd_length(previous - body.velocity)
            guard
                simd_length(body.velocity) < simd_length(previous),
                loss >= Self.minimumSpeedLoss, loss.isFinite
            else { continue }
            quiet[body.key] = Self.quietSteps
            hits.append(BodyCollision(
                body: body.key, position: body.position, speedLoss: loss, material: body.material,
                surface: body.surfaceMaterial
            ))
        }
        velocities = next
        quiet = quiet.filter { next[$0.key] != nil }
        return hits
    }
}

nonisolated extension BodyCollision {
    /// Louder for a harder hit: a quiet floor at the threshold, full level at `loudSpeedLoss`.
    public var gain: Float {
        let span = BodyCollisionTracker.loudSpeedLoss - BodyCollisionTracker.minimumSpeedLoss
        let share = (speedLoss - BodyCollisionTracker.minimumSpeedLoss) / span
        return BodyCollisionTracker.quietestGain
            + (1 - BodyCollisionTracker.quietestGain) * min(max(share, 0), 1)
    }
}
