// The stages of the world data load and how each one reports its time. The
// launcher lists them while it loads; Instruments shows them as signposts.

import Foundation
import OSLog

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

/// Times each stage, marks it as a signpost interval, and reports its start and end.
/// Stages run on several threads at once, so `report` must be thread-safe.
nonisolated public struct WorldLoadProgress: Sendable {
    private static let signposter = OSSignposter(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldLoad"
    )

    public static let silent = WorldLoadProgress { _ in }

    private let report: @Sendable (WorldLoadEvent) -> Void

    public init(report: @escaping @Sendable (WorldLoadEvent) -> Void) {
        self.report = report
    }

    /// Throws `CancellationError` instead of starting a stage once the load is cancelled.
    public func measure<Value>(
        _ stage: WorldLoadStage,
        _ body: () throws -> Value
    ) throws -> Value {
        try Task.checkCancellation()
        report(WorldLoadEvent(stage: stage, kind: .started))
        let signpost = Self.signposter.beginInterval(
            "stage",
            id: Self.signposter.makeSignpostID(),
            "\(stage.rawValue, privacy: .public)"
        )
        let start = ContinuousClock.now
        let value = try body()
        Self.signposter.endInterval("stage", signpost)
        report(WorldLoadEvent(stage: stage, kind: .finished(ContinuousClock.now - start)))
        return value
    }
}
