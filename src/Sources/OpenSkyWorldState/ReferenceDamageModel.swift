// What a destruction stage made a reference look like: a model swapped in, or the
// damage stage its own mesh shows. A cell build draws it
// (docs/engine/papyrus-destruction.md#in-the-game).

import Foundation

nonisolated public struct ReferenceDamageModel: WorldStateComponent, Hashable, Sendable {
    /// The stage's `DMDL` model, drawn in place of the base's; nil keeps the base's.
    public let path: String?
    /// The model damage stage whose `BSDamageStage` nodes are drawn; nil draws them all.
    public let stage: Int?

    public static var componentKind: WorldStateComponentKind {
        .damageModel
    }

    public init(path: String?, stage: Int? = nil) {
        self.path = path
        self.stage = stage
    }
}

nonisolated extension WorldStateComponentKind {
    public static let damageModel = Self(rawValue: "damageModel", order: 53)
}
