import Foundation
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRenderCore
import simd

/// One effect model the poser draws, for `game state effects`.
nonisolated public struct PosedEffectRow: Equatable, Sendable {
    public let effectID: Int
    public let modelPath: String
    public let bones: [String]

    public init(
        effectID: Int,
        modelPath: String,
        bones: [String]
    ) {
        self.effectID = effectID
        self.modelPath = modelPath
        self.bones = bones
    }
}
