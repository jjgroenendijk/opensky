import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One carried ingredient at the lab.
nonisolated public struct AlchemyIngredientReadout: Equatable, Sendable {
    public let id: FormID
    public let name: String
    public let count: Int32
    /// Each effect's name when the player knows it, by index; nil for an unknown one.
    public let effects: [String?]
    public let isChosen: Bool

    public init(id: FormID, name: String, count: Int32, effects: [String?], isChosen: Bool) {
        self.id = id
        self.name = name
        self.count = count
        self.effects = effects
        self.isChosen = isChosen
    }

    public var effectsText: String {
        effects.map { $0 ?? "?" }.joined(separator: ", ")
    }
}
