import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics
public import OpenSkyWorldState
public import simd

/// One cut head in flight or at rest.
nonisolated public struct SeveredHead: Sendable {
    /// About a human head's size, in engine units. OpenSky's number.
    public static let radius: Float = 10
    /// In kilograms, as clutter bodies are. OpenSky's number.
    public static let mass: Float = 5
    /// Speed away from the blow, in engine units per second. OpenSky's number.
    public static let launchSpeed: Float = 120
    /// Speed upwards at the cut, in engine units per second. OpenSky's number.
    public static let launchLift: Float = 160
    /// Turn at the cut, in radians per second, about the axis across the blow.
    public static let launchSpin: Float = 6

    public private(set) var body: DynamicBody
    /// Set once the resting place is in the death state, so it is written once.
    public var isRestRecorded = false
    /// Each bone at the cut, in the frame of the head body.
    let bonesInBody: [String: float4x4]
    private var accumulatedTime: Float = 0

    /// The head cut from `pose` at bone `node`. `away` is the blow's direction; nil drops
    /// the head without a push, as when a cut body loads again. A `rest` puts it there.
    public init?(
        key: ReferenceKey,
        cell: CellSceneLocation,
        node: String,
        pose: [String: float4x4],
        actorToWorld: float4x4,
        away: SIMD3<Float>? = nil,
        rest: ReferenceTransformOverride? = nil
    ) {
        guard let local = pose[node] else { return nil }
        let start = Self.rigidFrame(of: actorToWorld * local)
        let definition = DynamicBodyDefinition(
            volumes: [.radial(first: .zero, second: .zero, radius: Self.radius)], mass: Self.mass
        )
        var body = DynamicBody(
            key: key, reference: FormID(0), cell: cell, definition: definition,
            originPosition: Self.xyz(start.columns.3), orientation: simd_quatf(start)
        )
        if let away {
            let flat = SIMD3(away.x, away.y, 0)
            let direction = simd_length_squared(flat) > 1e-6 ? simd_normalize(flat) : .zero
            body.linearVelocity = direction * Self.launchSpeed + SIMD3(0, 0, Self.launchLift)
            body.angularVelocity = simd_cross(SIMD3(0, 0, 1), direction) * Self.launchSpin
        }
        if let rest {
            let placed = MatrixMath.placement(
                position: rest.position, rotation: rest.rotation, scale: 1
            )
            body.position = rest.position
            body.orientation = simd_quatf(Self.rigidFrame(of: placed))
            body.isSleeping = true
            isRestRecorded = true
        }
        self.body = body
        let toBody = (actorToWorld.inverse * start).inverse
        bonesInBody = pose.mapValues { toBody * $0 }
    }

    /// Steps the body in whole fixed steps, as dynamic bodies do.
    public mutating func advance(by frameTime: Float, world: DynamicStepWorld) {
        guard frameTime.isFinite else { return }
        accumulatedTime += min(max(frameTime, 0), PhysicsStep.maximumFrameTime)
        var bodies = [body]
        while accumulatedTime + Float.ulpOfOne >= PhysicsStep.fixedTimeStep {
            DynamicBodySolver.step(bodies: &bodies, world: world, dt: PhysicsStep.fixedTimeStep)
            accumulatedTime -= PhysicsStep.fixedTimeStep
        }
        body = bodies[0]
    }

    /// Where the head lies, for the death state.
    public var restTransform: ReferenceTransformOverride {
        ReferenceTransformOverride(
            position: body.position, rotation: MatrixMath.eulerAngles(of: body.orientation)
        )
    }

    /// The bone matrices that draw the head where its body is, in the actor's frame.
    public func bonePose(actorToWorld: float4x4) -> [String: float4x4] {
        let frame = actorToWorld.inverse * body.worldMatrix
        return bonesInBody.mapValues { frame * $0 }
    }

    /// `matrix` without its scale, so the sphere turns as the bone does.
    static func rigidFrame(of matrix: float4x4) -> float4x4 {
        func axis(_ column: SIMD4<Float>) -> SIMD4<Float> {
            let length = simd_length(xyz(column))
            return length > 1e-6 ? SIMD4(xyz(column) / length, 0) : SIMD4(0, 0, 0, 0)
        }
        var frame = float4x4(columns: (
            axis(matrix.columns.0), axis(matrix.columns.1), axis(matrix.columns.2),
            matrix.columns.3
        ))
        if frame.columns.0 == .zero || frame.columns.1 == .zero || frame.columns.2 == .zero {
            frame = float4x4(columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), matrix.columns.3
            ))
        }
        return frame
    }

    private static func xyz(_ vector: SIMD4<Float>) -> SIMD3<Float> {
        SIMD3(vector.x, vector.y, vector.z)
    }
}
