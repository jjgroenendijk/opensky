// The world archetypes that hold something while their spell is held: Detect Life's
// paint, a Telekinesis or Grab Actor hold, and a Guide trail. Pure rules over values.
// Quotes are from the Creation Kit wiki's Magic Effect page
// (<https://ck.uesp.net/wiki/Magic_Effect>). See docs/engine/magic-archetypes.md.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagicInterface
import simd

/// One running hold. A concentration spell lands once a second, and each landing
/// renews its hold; a hold no landing renews ends.
nonisolated struct MagicHold: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case detectLife
        case telekinesis
        case grabActor
        case guide
    }

    let kind: Kind
    /// Who cast it. Detect Life paints around it; a hold sits in front of it.
    let caster: ReferenceKey
    /// The MGEF, whose conditions, shader, or hazard the hold reads.
    let effect: ReferenceKey
    var remaining: Float
    /// The painted actors, the held body, or the grabbed actor.
    var held: [ReferenceKey]

    init(
        kind: Kind, caster: ReferenceKey, effect: ReferenceKey, remaining: Float,
        held: [ReferenceKey] = []
    ) {
        self.kind = kind
        self.caster = caster
        self.effect = effect
        self.remaining = remaining
        self.held = held
    }
}

nonisolated public enum MagicHoldCore {
    /// A concentration effect lands once a second, so a hold lives a little longer
    /// than that. An OpenSky number; the wiki only says the paint "will update".
    static let renewalSeconds: Float = 1.5
    /// How far in front of the caster a held object floats. An OpenSky number: the
    /// game settings give only the nearest distance.
    static let telekinesisHoldDistance: Float = 150
    /// How fast a released object leaves, world units per second. An OpenSky number.
    static let telekinesisThrowSpeed: Float = 1200
    /// How quickly a held object closes on its hold point, seconds.
    static let telekinesisSteerSeconds: Float = 0.15

    /// How long one landing keeps a hold: its duration, or until the next landing.
    static func lifetime(duration: Float) -> Float {
        max(duration, renewalSeconds)
    }

    /// `holds` with `hold` renewed in place, or added when no hold of its kind and
    /// caster runs.
    static func renewing(_ hold: MagicHold, in holds: [MagicHold]) -> [MagicHold] {
        var holds = holds
        if
            let index = holds
                .firstIndex(where: { $0.kind == hold.kind && $0.caster == hold.caster })
        {
            holds[index].remaining = max(holds[index].remaining, hold.remaining)
            return holds
        }
        return holds + [hold]
    }

    /// Ages every hold by `delta`. Returns the ones still running and the ones that ended.
    static func advancing(_ holds: [MagicHold], by delta: Float)
        -> (running: [MagicHold], ended: [MagicHold])
    {
        let aged = holds.map { hold in
            var hold = hold
            hold.remaining -= max(0, delta)
            return hold
        }
        return (aged.filter { $0.remaining > 0 }, aged.filter { $0.remaining <= 0 })
    }

    /// Where a self-cast light floats: the GMST offsets from the caster's eye, along
    /// its facing. `forward` is flattened, so looking down does not sink the light.
    public static func lightPosition(
        eye: SIMD3<Float>, forward: SIMD3<Float>, settings: MagicHoldSettings
    ) -> SIMD3<Float> {
        var flat = SIMD3<Float>(forward.x, forward.y, 0)
        flat = simd_length(flat) > 0 ? simd_normalize(flat) : SIMD3(0, 1, 0)
        let right = SIMD3<Float>(flat.y, -flat.x, 0)
        return eye + flat * settings.lightForwardOffset + right * settings.lightSideOffset
            + SIMD3(0, 0, settings.lightHeightOffset)
    }

    /// The impulse that steers a held body toward `point` this frame and carries its
    /// weight, so it floats there.
    static func steeringImpulse(
        _ body: MagicHeldBody, toward point: SIMD3<Float>, delta: Float, gravity: Float
    ) -> SIMD3<Float> {
        guard body.mass > 0, delta > 0 else { return .zero }
        let wanted = (point - body.position) / telekinesisSteerSeconds
        let lift = SIMD3<Float>(0, 0, gravity * delta)
        return (wanted - body.velocity + lift) * body.mass
    }

    /// Points along `path` every `spacing` units, at most `limit` of them, starting
    /// one spacing from its first point.
    static func trail(along path: [SIMD3<Float>], spacing: Float, limit: Int)
        -> [SIMD3<Float>]
    {
        guard spacing > 0, limit > 0, path.count > 1 else { return [] }
        var points: [SIMD3<Float>] = []
        var carried: Float = spacing
        for (from, to) in zip(path, path.dropFirst()) {
            let length = simd_distance(from, to)
            guard length > 0 else { continue }
            var along = carried
            while along <= length {
                points.append(from + (to - from) * (along / length))
                if points.count == limit {
                    return points
                }
                along += spacing
            }
            carried = along - length
        }
        return points
    }
}
