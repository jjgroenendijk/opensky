import Foundation
import OpenSkyFormatsCore

/// One step of the world data load, in the order the launcher lists them.
nonisolated public enum WorldLoadStage: String, CaseIterable, Sendable {
    case archives
    case masterFile
    case loadOrder
    case settings
    case magic
    case assetLibraries
    case weatherAndSound
    case items
    case crafting
    case equipment
    case dialogue
    case packages
    case factions
    case actorStats
    case quests
    case idlesAndEffects
    case menusAndMessages

    public var title: String {
        switch self {
        case .archives: "Archives"
        case .masterFile: "Skyrim.esm"
        case .loadOrder: "Load order"
        case .settings: "Game settings"
        case .magic: "Magic and perks"
        case .assetLibraries: "Mesh and texture libraries"
        case .weatherAndSound: "Weather and sound"
        case .items: "Items and inventories"
        case .crafting: "Crafting recipes"
        case .equipment: "Equipment"
        case .dialogue: "Dialogue"
        case .packages: "AI packages"
        case .factions: "Factions and locations"
        case .actorStats: "Actor stats"
        case .quests: "Quests and stories"
        case .idlesAndEffects: "Idles and effects"
        case .menusAndMessages: "Menus and messages"
        }
    }
}

nonisolated public struct WorldLoadEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case started
        case finished(Duration)
    }

    public let stage: WorldLoadStage
    public let kind: Kind

    public init(stage: WorldLoadStage, kind: Kind) {
        self.stage = stage
        self.kind = kind
    }
}
