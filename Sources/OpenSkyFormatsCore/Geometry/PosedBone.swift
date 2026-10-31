// One node of a posed skeleton or a model, in the model's space and in its parent's.

import simd

nonisolated public struct PosedBone: Equatable, Sendable {
    public let model: float4x4
    /// The node's transform inside its parent node: Gamebryo's "local" transform.
    public let local: float4x4

    public init(model: float4x4, local: float4x4) {
        self.model = model
        self.local = local
    }

    /// Bone `index` of model-space `matrices`. A bone without a posed parent is its
    /// own local transform.
    public init?(index: Int, matrices: [float4x4], parents: [Int]) {
        guard matrices.indices.contains(index) else { return nil }
        let parent = parents.indices.contains(index) ? parents[index] : -1
        let model = matrices[index]
        self.model = model
        local = matrices.indices.contains(parent) ? matrices[parent].inverse * model : model
    }
}
