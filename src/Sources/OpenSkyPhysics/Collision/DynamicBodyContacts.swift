// Narrowphase for dynamic rigid bodies against the static world: each contact is a
// sample point plus a skin radius tested against the other surface. `recoveryDepth`
// bounds how far behind a surface a contact is still believed. See
// docs/engine/dynamic-narrowphase.md.

public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import simd

/// Placed triangle geometry a penetration query runs against, bundled so the
/// query stays inside the strict parameter cap.
nonisolated struct PlacedTriangleSoup: Sendable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]
    let transform: float4x4
}

/// One body's contact samples in a placed shape's local space, with the box that
/// bounds them at full reach. Testing each triangle against the box first turns
/// many rejects into one. `recovery` sizes the box; see
/// `DynamicBodyContacts.recoveryDepth(of:)`.
nonisolated struct DynamicLocalSamples: Sendable {
    let points: [SIMD3<Float>]
    /// Each sample's skin, with `contactMargin` added and the shape's scale
    /// divided out, so every length below is in the shape's own units.
    let radii: [Float]
    /// How this shape's triangles are turned into surface normals, in the same
    /// local space the samples are in.
    let orientation: DynamicSurfaceOrientation
    /// `recoveryDepth` in the shape's units.
    let recovery: Float
    /// Sample AABB grown by the largest sample reach.
    let lower: SIMD3<Float>
    let upper: SIMD3<Float>

    /// Nil where the shape's placement will not invert or a sample does not
    /// survive the transform, which leaves the shape contributing no contact
    /// rather than a nonsense one.
    init?(
        samples: [(point: SIMD3<Float>, radius: Float)],
        shape: StaticCollisionShape,
        recovery worldRecovery: Float
    ) {
        let determinant = simd_determinant(shape.transform)
        let scale = DynamicCollisionMath.maximumScale(of: shape.transform)
        guard
            determinant.isFinite, abs(determinant) > 1e-9, scale > Float.ulpOfOne,
            !samples.isEmpty
        else { return nil }
        let inverse = shape.transform.inverse
        points = samples.map { DynamicCollisionMath.transform($0.point, by: inverse) }
        radii = samples.map { ($0.radius + DynamicBodyContacts.contactMargin) / scale }
        orientation = DynamicSurfaceOrientation.of(shape.geometry)
        recovery = worldRecovery / scale
        guard points.allSatisfy(\.isFiniteVector) else { return nil }
        let reach = (radii.max() ?? 0) + recovery
        var low = points[0]
        var high = points[0]
        for point in points.dropFirst() {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        lower = low - SIMD3(repeating: reach)
        upper = high + SIMD3(repeating: reach)
    }
}

/// One body of a touching pair, with its place in the solver's array.
nonisolated struct DynamicPairBody: Sendable {
    let body: DynamicBody
    let index: Int
}

/// The friction and restitution a pair of bodies contributes to its contacts.
nonisolated struct DynamicContactMaterial: Sendable {
    let friction: Float
    let restitution: Float
}

/// One resolved touch. `normal` always points away from the obstacle and toward
/// `body`, so a positive normal impulse separates them.
nonisolated public struct DynamicContact: Sendable {
    /// Index into the solver's body array.
    public let body: Int
    /// The other dynamic body, or nil for a contact against static geometry.
    public let other: Int?
    /// World-space contact point.
    public let point: SIMD3<Float>
    let normal: SIMD3<Float>
    /// Positive overlap along `normal`.
    let depth: Float
    let friction: Float
    let restitution: Float
    /// The `MATT` of what `body` touches: the static shape's, or the other body's.
    public var surfaceMaterial: FormID?
}

nonisolated public enum DynamicBodyContacts: Sendable {
    /// Collision margin every contact sample carries on top of its volume's own
    /// skin. A hull vertex has no skin of its own, so without a margin a resting
    /// box would generate contacts only while already interpenetrating and would
    /// jitter between touching and free. Engine units.
    public static let contactMargin: Float = 1.5

    /// How far behind a surface a contact is still believed, in engine units.
    /// Past it the sample is taken to belong to different geometry rather than
    /// to a deep penetration of this one.
    static let recoveryDepth: Float = 48

    /// The same bound for one body: the smaller of `recoveryDepth` and the body's own
    /// reach. Scaling it down for small clutter was the largest saving in the step.
    static func recoveryDepth(of body: DynamicBody) -> Float {
        min(recoveryDepth, max(contactMargin * 4, body.definition.boundingRadius))
    }
}
