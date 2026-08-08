// One simulated rigid body: the immutable inertial description built from
// decoded Havok data, and the mutable state the integrator advances (issue
// #193, roadmap item 15.2).
//
// Working units are the engine's, not Havok's. Lengths are Skyrim units,
// time is seconds, mass is kilograms, so gravity is `WalkController.gravity`
// and a metre-denominated field out of `NIFRigidBodyDynamics` is converted
// once, here, by `NIFCollisionModel.havokToEngineScale`. Inertia carries
// length squared and so converts by the square of it. Doing this at the
// boundary is why nothing below has to remember which unit a number is in.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

nonisolated extension simd_quatf {
    /// The no-rotation quaternion. `simd` supplies `matrix_identity_float4x4`
    /// but no quaternion equivalent, and a body placed by an unrotated
    /// reference needs one at every construction site.
    static let identityRotation = simd_quatf(real: 1, imag: .zero)
}

/// One decoded shape kept in its original form, so a moving body can be handed
/// to the player capsule's narrowphase as an ordinary placed collision shape.
/// The transform is centre-of-mass-local; composing it with the body's world
/// pose gives the same matrix a static placement would carry.
nonisolated struct DynamicBodyColliderShape: Sendable {
    let transform: float4x4
    let geometry: NIFCollisionGeometry
    let material: FormID?
}

/// The unchanging half of a body: its collider, its inertia, and the material
/// constants the solver reads. One definition per placed reference, shared by
/// every step it lives through.
nonisolated struct DynamicBodyDefinition: Sendable {
    /// Convex volumes in centre-of-mass-local space. More than one where the
    /// source `bhkRigidBody` carried several shapes.
    let volumes: [DynamicCollisionVolume]
    /// The same shapes undigested, for queries that want placed geometry rather
    /// than a convex volume: the player capsule, the interaction ray, and the
    /// shape sweeps.
    let colliderShapes: [DynamicBodyColliderShape]
    /// Kilograms; always positive and finite.
    let mass: Float
    let inverseMass: Float
    /// Body-local inverse inertia about the centre of mass, in 1/(kg unit^2).
    let inverseInertia: float3x3
    /// Where the centre of mass sits relative to the reference's own origin, in
    /// engine units. Persisting a resting transform needs it, because the store
    /// records the origin and the solver tracks the centre of mass.
    let centerOfMass: SIMD3<Float>
    /// Fraction of velocity shed per second.
    let linearDamping: Float
    let angularDamping: Float
    let friction: Float
    let restitution: Float
    let gravityFactor: Float
    /// Engine units per second.
    let maximumLinearSpeed: Float
    /// Radians per second.
    let maximumAngularSpeed: Float
    /// Farthest surface point from the centre of mass, over every volume.
    let boundingRadius: Float

    /// Vanilla clutter leaves the velocity ceilings at Havok's defaults, which
    /// are large enough that a body accelerating unchecked between two walls
    /// could still tunnel. These are the ceilings a body is held to when its
    /// own are absent or implausible; both are generous next to anything a fall
    /// or a shove produces.
    static let defaultMaximumLinearSpeed: Float = 8000
    static let defaultMaximumAngularSpeed: Float = 40

    /// One simulated rigid body for a whole placed reference, from every
    /// simulated `bhkRigidBody` its model carries, at the reference's uniform
    /// XSCL scale.
    ///
    /// It is deliberately *one* body per reference rather than one per decoded
    /// `bhkRigidBody`. A reference has a single `ReferenceKey`, a single drawn
    /// placement, and a single `.transform` component to persist into; a model
    /// whose several bodies were registered separately would collide on all
    /// three. Where a model does carry several — a cupboard with its doors — the
    /// bodies are welded into one rigid body: the masses add, the centre of mass
    /// is their mass-weighted mean, and every shape joins the collider. That is
    /// the right answer until joints are solved (item 15.6), because an
    /// unjointed multi-body model would otherwise fly apart.
    ///
    /// Everything stays in the reference's own model space — each body's
    /// model-local transform is folded in, the placement's rotation and
    /// translation are not, because those are the pose `DynamicBody` integrates
    /// and a definition is shared across steps.
    ///
    /// Nil where nothing is simulable: no body has a known simulated motion
    /// system with a positive finite mass, or no convex volume survived.
    init?(
        bodies: [NIFCollisionBody],
        referenceScale: Float,
        materials: MaterialTypeIndex? = nil
    ) {
        guard referenceScale > 0, referenceScale.isFinite else { return nil }
        let simulated = bodies.filter(\.dynamics.isSimulated)
        guard !simulated.isEmpty else { return nil }
        let scaling = MatrixMath.scale(uniform: referenceScale)
        let totalMass = simulated.reduce(0) { $0 + $1.dynamics.mass }
        guard totalMass > 0, totalMass.isFinite else { return nil }
        var center = SIMD3<Float>.zero
        for body in simulated {
            center += DynamicCollisionMath.transform(
                body.dynamics.centerOfMass, by: scaling * body.transform
            ) * (body.dynamics.mass / totalMass)
        }
        guard center.isFiniteVector else { return nil }
        let collider = Self.collider(
            of: simulated, scaling: scaling, center: center, materials: materials
        )
        let placed = collider.volumes
        guard !placed.isEmpty else { return nil }
        let scale = NIFCollisionModel.havokToEngineScale * referenceScale
        // The heaviest body's material constants speak for the welded whole,
        // which is the least arbitrary choice available and matches the single-
        // body case exactly.
        let dominant = simulated.max { $0.dynamics.mass < $1.dynamics.mass }?.dynamics
            ?? simulated[0].dynamics
        volumes = placed
        colliderShapes = collider.shapes
        centerOfMass = center
        mass = totalMass
        inverseMass = 1 / totalMass
        // A decoded tensor describes one body about its own centre. Welding
        // several moves that centre, so the union's box stands in instead;
        // a lone body keeps the tensor the file authored.
        inverseInertia = simulated.count == 1
            ? Self.resolvedInverseInertia(
                of: dominant, volumes: placed, mass: totalMass, scale: scale
            )
            : Self.boxInverseInertia(volumes: placed, mass: totalMass)
        linearDamping = Self.clampedDamping(dominant.linearDamping)
        angularDamping = Self.clampedDamping(dominant.angularDamping)
        friction = Self.clamped(dominant.friction, low: 0, high: 4, fallback: 0.5)
        restitution = Self.clamped(dominant.restitution, low: 0, high: 1, fallback: 0.2)
        gravityFactor = Self.clamped(dominant.gravityFactor, low: 0, high: 4, fallback: 1)
        maximumLinearSpeed = Self.clamped(
            dominant.maxLinearVelocity * scale,
            low: 1,
            high: Self.defaultMaximumLinearSpeed,
            fallback: Self.defaultMaximumLinearSpeed
        )
        maximumAngularSpeed = Self.clamped(
            dominant.maxAngularVelocity,
            low: 0.1,
            high: Self.defaultMaximumAngularSpeed,
            fallback: Self.defaultMaximumAngularSpeed
        )
        boundingRadius = placed.reduce(0) { max($0, $1.boundingRadius) }
    }

    /// Every simulated body's shapes as convex volumes and as placed geometry,
    /// both re-expressed against the welded centre of mass — which is the origin
    /// the solver integrates about. A shape that yields no convex volume is
    /// dropped from both, so the two stay index-aligned.
    private static func collider(
        of bodies: [NIFCollisionBody],
        scaling: float4x4,
        center: SIMD3<Float>,
        materials: MaterialTypeIndex?
    ) -> (volumes: [DynamicCollisionVolume], shapes: [DynamicBodyColliderShape]) {
        let recentre = MatrixMath.translation(-center)
        var volumes: [DynamicCollisionVolume] = []
        var shapes: [DynamicBodyColliderShape] = []
        for body in bodies {
            let transform = scaling * body.transform
            for shape in body.shapes {
                let matrix = recentre * transform * shape.transform
                guard
                    let volume = DynamicCollisionVolume.make(from: shape.geometry)?
                        .transformed(by: matrix)
                else { continue }
                volumes.append(volume)
                shapes.append(DynamicBodyColliderShape(
                    transform: matrix,
                    geometry: shape.geometry,
                    material: shape.material.flatMap { materials?.material(forHavokMaterial: $0) }
                ))
            }
        }
        return (volumes: volumes, shapes: shapes)
    }

    /// A definition assembled directly, for tests and for the dropped-item path
    /// that has a shape and a mass but no decoded `bhkRigidBody` behind it.
    init(
        volumes: [DynamicCollisionVolume],
        mass: Float,
        colliderShapes: [DynamicBodyColliderShape] = [],
        friction: Float = 0.5,
        restitution: Float = 0.2,
        damping: (linear: Float, angular: Float) = (0.1, 0.05)
    ) {
        self.volumes = volumes
        self.colliderShapes = colliderShapes
        self.mass = max(mass, .leastNormalMagnitude)
        inverseMass = 1 / self.mass
        inverseInertia = Self.boxInverseInertia(volumes: volumes, mass: self.mass)
        centerOfMass = .zero
        linearDamping = Self.clampedDamping(damping.linear)
        angularDamping = Self.clampedDamping(damping.angular)
        self.friction = friction
        self.restitution = restitution
        gravityFactor = 1
        maximumLinearSpeed = Self.defaultMaximumLinearSpeed
        maximumAngularSpeed = Self.defaultMaximumAngularSpeed
        boundingRadius = volumes.reduce(0) { max($0, $1.boundingRadius) }
    }

    /// The decoded tensor where it inverts cleanly, and the collider's own box
    /// approximation where it does not.
    ///
    /// Vanilla writes an inertia tensor for every dynamic body, but a modded or
    /// truncated one can be singular or scaled for a different unit system, and
    /// a bad tensor makes a body spin without bound. Falling back to a tensor
    /// derived from the shape the solver is actually going to collide keeps
    /// such a body plausible instead of explosive.
    private static func resolvedInverseInertia(
        of dynamics: NIFRigidBodyDynamics,
        volumes: [DynamicCollisionVolume],
        mass: Float,
        scale: Float
    ) -> float3x3 {
        let converted = dynamics.inertiaTensor * (scale * scale)
        let determinant = converted.determinant
        guard determinant.isFinite, abs(determinant) > 1e-6 else {
            return boxInverseInertia(volumes: volumes, mass: mass)
        }
        let inverse = converted.inverse
        let columns = [inverse.columns.0, inverse.columns.1, inverse.columns.2]
        guard columns.allSatisfy(\.isFiniteVector) else {
            return boxInverseInertia(volumes: volumes, mass: mass)
        }
        return inverse
    }

    /// Inverse inertia of a solid box with the collider's own extents, which is
    /// the standard stand-in when a body's authored tensor is unusable.
    private static func boxInverseInertia(
        volumes: [DynamicCollisionVolume],
        mass: Float
    ) -> float3x3 {
        var bounds: ModelBounds?
        for volume in volumes {
            let local = volume.localBounds
            bounds = bounds.map { $0.union(local) } ?? local
        }
        guard let bounds else { return matrix_identity_float3x3 }
        let extents = simd_max(bounds.max - bounds.min, SIMD3(repeating: 1))
        let squared = extents * extents
        let factor = mass / 12
        let diagonal = SIMD3<Float>(
            factor * (squared.y + squared.z),
            factor * (squared.x + squared.z),
            factor * (squared.x + squared.y)
        )
        return float3x3(diagonal: 1 / simd_max(diagonal, SIMD3(repeating: .leastNormalMagnitude)))
    }

    private static func clampedDamping(_ value: Float) -> Float {
        clamped(value, low: 0, high: 10, fallback: 0)
    }

    private static func clamped(
        _ value: Float,
        low: Float,
        high: Float,
        fallback: Float
    ) -> Float {
        guard value.isFinite else { return fallback }
        return min(max(value, low), high)
    }
}

/// A body's pose and motion. Position is the centre of mass, because that is
/// the point every impulse is measured against; `originPosition` recovers the
/// reference's own origin for rendering and for persistence.
nonisolated struct DynamicBody: Sendable {
    /// Session-stable identity, and the solver's iteration order: bodies step
    /// in ascending key so that two runs of the same scene produce the same
    /// trajectories.
    let key: ReferenceKey
    /// The placed reference this body stands for, for query attribution.
    let reference: FormID
    /// The cell whose record placed this reference. It remains authoritative
    /// for rebuilds and persistence even after the body crosses a boundary.
    let placingCell: CellSceneLocation
    /// The cell containing the live origin. Exterior integration updates this
    /// at the end of every fixed step; interiors never re-bin.
    var occupiedCell: CellSceneLocation
    let definition: DynamicBodyDefinition
    var position: SIMD3<Float>
    var orientation: simd_quatf
    var linearVelocity: SIMD3<Float> = .zero
    var angularVelocity: SIMD3<Float> = .zero
    /// True once the body has been still long enough to stop being integrated.
    var isSleeping = false
    /// Consecutive steps spent below the sleep thresholds.
    var restingSteps = 0

    init(
        key: ReferenceKey,
        reference: FormID,
        cell: CellSceneLocation,
        definition: DynamicBodyDefinition,
        originPosition: SIMD3<Float>,
        orientation: simd_quatf
    ) {
        self.key = key
        self.reference = reference
        placingCell = cell
        occupiedCell = cell
        self.definition = definition
        self.orientation = orientation
        position = originPosition + orientation.act(definition.centerOfMass)
    }

    /// Where the reference's own origin sits, which is what a transform
    /// override records and what a draw call places the mesh by.
    var originPosition: SIMD3<Float> {
        position - orientation.act(definition.centerOfMass)
    }

    /// World AABB of every volume at the current pose, inflated by the
    /// bounding-sphere radius so it stays valid through one step's rotation.
    var worldBounds: ModelBounds {
        let extent = SIMD3<Float>(repeating: definition.boundingRadius)
        return ModelBounds(min: position - extent, max: position + extent)
    }

    /// Pose as a matrix: the frame every centre-of-mass-local shape transform
    /// composes with to land in the world.
    var worldMatrix: float4x4 {
        MatrixMath.translation(position) * float4x4(orientation)
    }

    /// How far this body has moved from the pose its cell build drew it at, as
    /// the rigid transform that carries the one onto the other (issue #193).
    ///
    /// A cell build bakes `T(position) * R(rotation) * S(scale)` into every
    /// instance matrix, and a body's own placed pose is the same translation
    /// and rotation without the scale. So `delta * baked` is the live matrix
    /// for every mesh of the reference, whatever the scale and whatever local
    /// transform the mesh carries, and no draw call has to know which is which.
    /// Nil when nothing has moved, which is the resting case and keeps the map
    /// the renderer consults empty in a world that is standing still.
    func instanceDelta(
        fromPlacedPosition placed: SIMD3<Float>,
        orientation placedOrientation: simd_quatf
    ) -> float4x4? {
        let origin = originPosition
        guard origin != placed || orientation != placedOrientation else { return nil }
        let rotation = orientation * placedOrientation.inverse
        return MatrixMath.translation(origin)
            * float4x4(rotation)
            * MatrixMath.translation(-placed)
    }

    /// The body's shapes as ordinary placed collision shapes at the current
    /// pose, so the player capsule, the interaction ray, and the shape sweeps
    /// see moving clutter through exactly the query they already use for the
    /// static world.
    func placedShapes() -> [StaticCollisionShape] {
        let matrix = worldMatrix
        return definition.colliderShapes.compactMap { shape in
            let transform = matrix * shape.transform
            guard let local = NIFCollisionModel.bounds(of: shape.geometry) else { return nil }
            return StaticCollisionShape(
                reference: reference,
                transform: transform,
                geometry: shape.geometry,
                bounds: local.transformed(by: transform),
                material: shape.material
            )
        }
    }

    /// Velocity of the material point currently at `worldPoint`.
    func velocity(at worldPoint: SIMD3<Float>) -> SIMD3<Float> {
        linearVelocity + simd_cross(angularVelocity, worldPoint - position)
    }

    /// World-space inverse inertia, which is the body-local tensor rotated into
    /// the pose the impulse is applied at.
    var worldInverseInertia: float3x3 {
        let rotation = float3x3(orientation)
        return rotation * definition.inverseInertia * rotation.transpose
    }

    /// Applies an impulse at a world point, waking the body. Kilogram engine
    /// units per second, the same units `linearVelocity` is in times the mass.
    mutating func applyImpulse(_ impulse: SIMD3<Float>, at worldPoint: SIMD3<Float>) {
        guard impulse.isFiniteVector, simd_length_squared(impulse) > Float.ulpOfOne else {
            return
        }
        wake()
        linearVelocity += impulse * definition.inverseMass
        angularVelocity += worldInverseInertia * simd_cross(worldPoint - position, impulse)
    }

    mutating func wake() {
        isSleeping = false
        restingSteps = 0
    }

    /// Contact samples of every volume, paired with the skin each carries.
    func contactSamples() -> [(point: SIMD3<Float>, radius: Float)] {
        definition.volumes.flatMap { volume in
            volume.contactSamples(position: position, orientation: orientation)
                .map { (point: $0, radius: volume.skinRadius) }
        }
    }

    /// How deep a world-space sphere sits inside this body, taking the deepest
    /// of its volumes. The normal points out of the body.
    func penetration(of worldPoint: SIMD3<Float>, radius: Float) -> DynamicPenetration? {
        let inverse = orientation.inverse
        let local = inverse.act(worldPoint - position)
        var deepest: DynamicPenetration?
        for volume in definition.volumes {
            guard let hit = volume.penetration(of: local, radius: radius) else { continue }
            if hit.depth > (deepest?.depth ?? -.greatestFiniteMagnitude) {
                deepest = hit
            }
        }
        return deepest.map {
            DynamicPenetration(normal: orientation.act($0.normal), depth: $0.depth)
        }
    }
}
