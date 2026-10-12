// The lit-surface terms of a material past the diffuse: normal space, specular,
// glow, soft, rim and back light, detail, environment, parallax and the tint
// colour. Which flag and slot turns each on: docs/formats/nif-materials.md.

import Foundation
import simd

nonisolated public struct SurfaceShading: Hashable, Sendable {
    public struct Terms: OptionSet, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// The normal map holds model-space normals, not tangent-space ones.
        public static let modelSpaceNormals = Terms(rawValue: 1 << 0)
        public static let specular = Terms(rawValue: 1 << 1)
        /// Specular strength comes from `backLightTexture` instead of the normal alpha.
        public static let specularMap = Terms(rawValue: 1 << 2)
        public static let emissive = Terms(rawValue: 1 << 3)
        /// `glowTexture` scales the emissive colour.
        public static let glowMap = Terms(rawValue: 1 << 4)
        /// `glowTexture` is a light mask for soft and rim light.
        public static let softLighting = Terms(rawValue: 1 << 5)
        public static let rimLighting = Terms(rawValue: 1 << 6)
        public static let backLighting = Terms(rawValue: 1 << 7)
        /// `detailTexture` is the FaceGen detail map, overlay-blended then doubled.
        public static let faceDetail = Terms(rawValue: 1 << 8)
        public static let environment = Terms(rawValue: 1 << 9)
        /// `environmentMaskTexture` scales the reflection instead of the normal alpha.
        public static let environmentMask = Terms(rawValue: 1 << 10)
        /// `detailTexture` is a height map that shifts the texture coordinate.
        public static let parallax = Terms(rawValue: 1 << 11)
        /// `innerLayerTexture` shows under the diffuse, shifted by the view.
        public static let multiLayer = Terms(rawValue: 1 << 12)
    }

    public var terms: Terms = []
    public var emissiveColor: SIMD3<Float> = .zero
    public var emissiveMultiple: Float = 0
    /// Soft-light wrap.
    public var lightingEffect1: Float = 0.3
    /// Rim-light power.
    public var lightingEffect2: Float = 2
    /// The skin or hair tint colour a NIF stores. An actor's own colour replaces it.
    public var tintColor: SIMD3<Float>?
    public var environmentScale: Float = 1
    public var multiLayer = MultiLayer()
    /// Slot 2: glow map, or the soft and rim light mask.
    public var glowTexture: String?
    /// Slot 3: FaceGen detail map or parallax height map.
    public var detailTexture: String?
    /// Slot 4: cube map.
    public var environmentTexture: String?
    /// Slot 5.
    public var environmentMaskTexture: String?
    /// Slot 6 of a multi-layer shape.
    public var innerLayerTexture: String?
    /// Slot 7: back light map, or the specular map of a model-space shape.
    public var backLightTexture: String?

    public struct MultiLayer: Hashable, Sendable {
        public var thickness: Float = 5
        public var refractionScale: Float = 0.25
        public var innerScale = SIMD2<Float>(1, 1)
        public var environmentStrength: Float = 1

        public init() {}

        public init(
            thickness: Float,
            refractionScale: Float,
            innerScale: SIMD2<Float>,
            environmentStrength: Float
        ) {
            self.thickness = thickness
            self.refractionScale = refractionScale
            self.innerScale = innerScale
            self.environmentStrength = environmentStrength
        }
    }

    public init() {}

    public static let plain = SurfaceShading()

    /// Every texture key, for preloading.
    public var textureKeys: [String] {
        [
            glowTexture, detailTexture, environmentTexture, environmentMaskTexture,
            innerLayerTexture, backLightTexture
        ].compactMap(\.self)
    }
}
