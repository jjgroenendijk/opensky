// The stages one hit took a destructible reference through, for the session to show:
// the model swap, the damage over time, the debris, and the explosion.
// See docs/engine/papyrus-destruction.md#in-the-game.

public import OpenSkyFormatsESM

nonisolated public struct DestructionStageChange: Equatable, Sendable {
    nonisolated public struct Stage: Equatable, Sendable {
        /// The stage's `DMDL` model, which replaces the reference's own.
        public let model: String?
        /// The `BSDamageStage` nodes a stage without a model shows in the reference's mesh.
        public var modelDamageStage = 0
        public let selfDamagePerSecond: Float
        public let explosion: ReferenceKey?
        public let debris: ReferenceKey?
        public let debrisCount: Int

        public init(
            model: String? = nil, selfDamagePerSecond: Float = 0,
            explosion: ReferenceKey? = nil, debris: ReferenceKey? = nil, debrisCount: Int = 0
        ) {
            self.model = model
            self.selfDamagePerSecond = selfDamagePerSecond
            self.explosion = explosion
            self.debris = debris
            self.debrisCount = debrisCount
        }
    }

    public let reference: ReferenceKey
    /// The stages passed, in record order.
    public let stages: [Stage]
    /// The centre of the base's `OBND` box, in the reference's own frame.
    public var boundsCentre: SIMD3<Float> = .zero
    /// Half the box's diagonal: how far a stage's explosion may move from the centre.
    public var boundRadius: Float = 0

    public init(reference: ReferenceKey, stages: [Stage]) {
        self.reference = reference
        self.stages = stages
    }
}
