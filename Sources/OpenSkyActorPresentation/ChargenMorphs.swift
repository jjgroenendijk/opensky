// Race menu face values as chargen TRI morph weights, and the vertex positions
// they give. Slider order and the sign of each pair: docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsMesh
import simd

nonisolated public enum ChargenMorphs {
    /// One NAM9 slider: the TRI target for a negative value, then for a positive one.
    nonisolated public struct SliderPair: Equatable, Sendable {
        public let negative: String
        public let positive: String
    }

    /// NAM9 order. The vampire slider (the last one) drives one target only.
    public static let sliders: [SliderPair] = [
        SliderPair(negative: "NoseShort", positive: "NoseLong"),
        SliderPair(negative: "NoseDown", positive: "NoseUp"),
        SliderPair(negative: "JawUp", positive: "JawDown"),
        SliderPair(negative: "JawNarrow", positive: "JawWide"),
        SliderPair(negative: "JawBack", positive: "JawForward"),
        SliderPair(negative: "CheeksDown", positive: "CheeksUp"),
        SliderPair(negative: "CheeksIn", positive: "CheeksOut"),
        SliderPair(negative: "EyesMoveDown", positive: "EyesMoveUp"),
        SliderPair(negative: "EyesMoveIn", positive: "EyesMoveOut"),
        SliderPair(negative: "BrowDown", positive: "BrowUp"),
        SliderPair(negative: "BrowIn", positive: "BrowOut"),
        SliderPair(negative: "BrowBack", positive: "BrowForward"),
        SliderPair(negative: "LipMoveDown", positive: "LipMoveUp"),
        SliderPair(negative: "LipMoveIn", positive: "LipMoveOut"),
        SliderPair(negative: "ChinThin", positive: "ChinWide"),
        SliderPair(negative: "ChinMoveUp", positive: "ChinMoveDown"),
        SliderPair(negative: "Overbite", positive: "Underbite"),
        SliderPair(negative: "EyesBack", positive: "EyesForward")
    ]
    public static let vampireTarget = "VampireMorph"
    /// NAMA groups that pick a numbered target; index 1 is unused.
    public static let partPrefixes: [Int: String] = [0: "NoseType", 2: "EyesType", 3: "LipType"]

    /// Target weights in 0...1. A zero slider or part 0 adds no target.
    public static func weights(morphs: [Float], parts: [Int32]) -> [String: Float] {
        var weights: [String: Float] = [:]
        for (index, value) in morphs.prefix(sliders.count).enumerated() where value != 0 {
            let pair = sliders[index]
            weights[value < 0 ? pair.negative : pair.positive] = min(abs(value), 1)
        }
        if morphs.count > sliders.count, morphs[sliders.count] > 0 {
            weights[vampireTarget] = min(morphs[sliders.count], 1)
        }
        for (index, prefix) in partPrefixes.sorted(by: { $0.key < $1.key })
            where index < parts.count && parts[index] > 0
        {
            weights["\(prefix)\(parts[index])"] = 1
        }
        return weights
    }

    /// Base vertices plus each weighted target's scaled deltas. Unknown names are
    /// skipped; a target with a different vertex count is skipped too.
    public static func positions(tri: TRIFile, weights: [String: Float]) -> [SIMD3<Float>] {
        var result = tri.baseVertices
        for target in tri.morphTargets {
            guard
                let weight = weights[target.name], weight != 0,
                target.deltas.count == result.count
            else { continue }
            let factor = target.scale * weight
            for index in result.indices {
                result[index] += target.deltas[index] * factor
            }
        }
        return result
    }

    /// Body weight blends the thin `_0` and heavy `_1` meshes; 0...100.
    public static func blend(
        thin: [SIMD3<Float>], heavy: [SIMD3<Float>], weight: Float
    ) -> [SIMD3<Float>]? {
        guard thin.count == heavy.count else { return nil }
        let amount = min(max(weight, 0), 100) / 100
        return zip(thin, heavy).map { simd_mix($0, $1, SIMD3(repeating: amount)) }
    }
}
