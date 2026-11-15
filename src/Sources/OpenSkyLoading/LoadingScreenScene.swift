// The game's loading screen scene: a fixed camera, the model at the origin, three
// lights, and a mist. It is drawn apart from the world, in its own space. The
// values and the order of each step: docs/engine/loading-screens.md#the-games-scene.

import OpenSkyFormatsESM
public import OpenSkyRenderCore
public import simd

nonisolated public enum LoadingScreenScene {
    /// Where the camera stands with no path, and the point it looks at.
    public static let cameraBase = SIMD3<Float>(-50, 600, 80)
    static let cameraTarget = SIMD3<Float>(-50, 0, 0)

    public static let defaultFieldOfView: Float = 75
    /// A change that leaves this open range is ignored.
    static let fieldOfViewLimits: (low: Float, high: Float) = (60, 95)

    public static let mistPath = "meshes\\Interface\\INTMenuFogParticles.nif"

    /// The game reads the field of view value in its own unit, not degrees: at 75 the
    /// view is about 17 degrees wide.
    public static func horizontalFieldOfView(_ value: Float) -> Float {
        2 * atanf(0.75 * tanf(value * .pi / 1200))
    }

    /// The camera for a path node at `node`: X and Y are subtracted, Z is added.
    /// The camera keeps the base look direction.
    public static func camera(pathNode node: SIMD3<Float> = .zero) -> FreeFlyCamera {
        let direction = cameraTarget - cameraBase
        return FreeFlyCamera(
            position: SIMD3(cameraBase.x - node.x, cameraBase.y - node.y, cameraBase.z + node.z),
            yaw: atan2f(direction.y, direction.x),
            pitch: atan2f(direction.z, simd_length(SIMD2(direction.x, direction.y)))
        )
    }

    /// What places the screen's model.
    nonisolated public struct ModelPose: Equatable, Sendable {
        /// RNAM, whole degrees per axis.
        public var rotationDegrees: SIMD3<Float>
        /// SNAM; its sign is dropped.
        public var scale: Float
        /// XNAM.
        public var translation: SIMD3<Float>
        /// The player's turn about the scene's vertical axis.
        public var turnRadians: Float
        /// The model's inventory marker turn, radians per axis, when it has one.
        public var markerRotation: SIMD3<Float>?

        public init(
            rotationDegrees: SIMD3<Float>, scale: Float, translation: SIMD3<Float>,
            turnRadians: Float = 0, markerRotation: SIMD3<Float>? = nil
        ) {
            self.rotationDegrees = rotationDegrees
            self.scale = scale
            self.translation = translation
            self.turnRadians = turnRadians
            self.markerRotation = markerRotation
        }
    }

    /// The model's place in the scene. A screen wider than 16:9 shrinks the scale
    /// and the offset, so the model keeps its size against the screen's height.
    public static func modelTransform(_ pose: ModelPose, aspectRatio: Float) -> float4x4 {
        let wide = aspectRatio > wideAspect ? wideAspect / aspectRatio : 1
        let base = pose.markerRotation.map(eulerRotation) ?? simd_quatf(
            angle: .pi, axis: SIMD3(0, 0, 1)
        )
        let initial = eulerRotation(pose.rotationDegrees * (.pi / 180))
        let turn = simd_quatf(angle: pose.turnRadians, axis: SIMD3(0, 0, 1))
        let scale = abs(pose.scale) * wide
        var matrix = float4x4(turn * initial * base)
            * float4x4(diagonal: SIMD4(scale, scale, scale, 1))
        matrix.columns.3 = SIMD4(pose.translation * wide, 1)
        return matrix
    }

    static let wideAspect: Float = 16.0 / 9.0

    /// The game builds a turn from three angles as a NIF matrix, which acts on row
    /// vectors, so for column vectors each angle turns the other way
    /// (docs/formats/nif-extra-data.md).
    static func eulerRotation(_ radians: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: -radians.z, axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: -radians.y, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -radians.x, axis: SIMD3(1, 0, 0))
    }

    /// The mist stands at the origin, turned half a turn about Z.
    public static let mistTransform = float4x4(simd_quatf(angle: -.pi, axis: SIMD3(0, 0, 1)))

    /// Three fixed point lights. Only the first casts a shadow.
    public static let lights: [RenderPointLight] = [
        light(
            at: SIMD3(-160, 160, 128),
            SIMD3(0.96, 0.96, 0.82),
            radius: 1500,
            dimmer: 1.6,
            castsShadows: true
        ),
        light(at: SIMD3(160, -96, 160), SIMD3(0.70, 0.81, 0.80), radius: 1024, dimmer: 3.0),
        light(at: SIMD3(128, 160, -96), SIMD3(1, 1, 1), radius: 1024, dimmer: 0.1)
    ]

    /// A LIGH record's falloff when it gives none; the scene's lights give none.
    static let falloffExponent: Float = 1

    private static func light(
        at position: SIMD3<Float>, _ colour: SIMD3<Float>, radius: Float, dimmer: Float,
        castsShadows: Bool = false
    ) -> RenderPointLight {
        RenderPointLight(
            position: position, radius: radius, color: colour * dimmer,
            falloffExponent: falloffExponent, castsShadows: castsShadows
        )
    }

    /// No sun and a black ambient from every side, so only the three lights show.
    public static let lighting = RenderLighting(
        ambientColor: .zero,
        directionalAmbient: DirectionalAmbientColors(
            positiveX: .zero, negativeX: .zero, positiveY: .zero,
            negativeY: .zero, positiveZ: .zero, negativeZ: .zero
        ),
        directionalDirection: SIMD3(0, 0, -1),
        directionalColor: .zero,
        fog: nil
    )
}
