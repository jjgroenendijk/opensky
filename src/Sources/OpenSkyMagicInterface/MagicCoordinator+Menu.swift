import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One known spell as the magic menu lists it.
nonisolated public struct MagicMenuSpell: Equatable, Sendable {
    public let name: String
    /// "spell", "power", or "ability", from the load order's texts.
    public let typeName: String
    public let isReadied: Bool
    /// The tab's title: a school, "SHOUTS", or "POWERS", or nil for no tab of its own.
    public let category: String?

    public init(
        name: String,
        typeName: String,
        isReadied: Bool,
        category: String? = nil
    ) {
        self.name = name
        self.typeName = typeName
        self.isReadied = isReadied
        self.category = category
    }
}
