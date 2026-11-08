// Global data tables on the write side: the decoded tables, and the empty form of every
// other one, laid out as UESP documents each table with its counts at zero.
// See docs/formats/ess.md#global-data-tables and #writing.

import Foundation

nonisolated extension ESSMiscStat {
    public static func table(_ stats: [Self]) throws(ESSError) -> ESSGlobalData {
        try ESSGlobalData(type: .miscStats) { writer throws(ESSError) in
            try writer.count32(stats.count, "misc stats")
            for stat in stats {
                try writer.wstring(stat.name, "misc stat name")
                writer.uint8(stat.category)
                writer.int32(stat.value)
            }
        }
    }
}

nonisolated extension ESSPlayerLocation {
    public func table() throws(ESSError) -> ESSGlobalData {
        try ESSGlobalData(type: .playerLocation) { writer in
            writer.uint32(nextObjectID)
            writer.refID(worldspace)
            writer.int32(cell.x)
            writer.int32(cell.y)
            writer.refID(space)
            writer.vector3(position)
            // UESP's trailing unknown byte; the reader ignores it.
            writer.uint8(0)
        }
    }
}

nonisolated extension ESSGlobalVariable {
    public static func table(_ globals: [Self]) throws(ESSError) -> ESSGlobalData {
        try ESSGlobalData(type: .globalVariables) { writer throws(ESSError) in
            try writer.count(globals.count, "global variables")
            for global in globals {
                writer.refID(global.global)
                writer.float32(global.value)
            }
        }
    }
}

nonisolated extension ESSWeather {
    /// The documented prefix, then UESP's unknown fields as zero and no optional parts.
    public func table() throws(ESSError) -> ESSGlobalData {
        try ESSGlobalData(type: .weather) { writer in
            let null = ESSRefID(raw: 0)
            for ref in [climate, weather, previousWeather, null, null, regionWeather] {
                writer.refID(ref)
            }
            writer.float32(currentHour)
            writer.float32(currentHour)
            writer.float32(transition)
            writer.bytes(Data(count: 6 * 4 + 4 + 4))
            writer.uint8(0)
        }
    }
}

nonisolated extension ESSGlobalData {
    init(
        type: ESSGlobalDataType, _ body: (inout ESSWriter) throws(ESSError) -> Void
    ) throws(ESSError) {
        try self.init(type: type.rawValue, data: ESSWriter.build(body))
    }

    /// Table types in file order, per group.
    public static let group1Types: [ESSGlobalDataType] = [
        .miscStats, .playerLocation, .tes, .globalVariables, .createdObjects, .effects,
        .weather, .audio, .skyCells
    ]
    public static let group2Types: [ESSGlobalDataType] = [
        .processLists, .combat, .interface, .actorCauses, .unknown104, .detectionManager,
        .locationMetaData, .questStaticData, .storyTeller, .magicFavorites, .playerControls,
        .storyEventManager, .ingredientShared, .menuControls, .menuTopicManager
    ]
    public static let group3Types: [ESSGlobalDataType] = [
        .tempEffects, .papyrus, .animObjects, .timer, .synchronizedAnimations, .main
    ]

    /// The table with every count at zero and every unknown field zero. Types 104
    /// and 1004 have no documented layout and are written with no bytes.
    public static func empty(_ type: ESSGlobalDataType) throws(ESSError) -> Self {
        switch type {
        case .playerLocation:
            return try ESSPlayerLocation(
                nextObjectID: 0, worldspace: ESSRefID(raw: 0), cell: .zero,
                space: ESSRefID(raw: 0), position: .zero
            ).table()
        case .weather:
            let null = ESSRefID(raw: 0)
            return try ESSWeather(
                climate: null, weather: null, previousWeather: null, regionWeather: null,
                currentHour: 0, transition: 0
            ).table()
        case .papyrus:
            return try ESSPapyrusWriter().table()
        default:
            return Self(type: type.rawValue, data: emptyLayout(type))
        }
    }

    /// Zero bytes per empty table, from UESP's layouts: a zero count is one `vsval` byte
    /// or a four-byte `uint32`, a null ref id three bytes, and a float four.
    private static let emptySizes: [ESSGlobalDataType: Int] = [
        .miscStats: 4, .tes: 1 + 4 + 1, .globalVariables: 1, .createdObjects: 4,
        .effects: 1 + 4 + 4, .audio: 3 + 1 + 3, .skyCells: 1, .processLists: 3 * 4 + 4 + 7,
        .combat: 4 + 1 + 1 + 4 + 1 + 1 + 4 + 4 * 4, .interface: 4 + 1 + 3 + 1,
        .actorCauses: 4 + 1, .detectionManager: 1, .locationMetaData: 1,
        .storyTeller: 1, .magicFavorites: 2, .playerControls: 3 + 2 + 1,
        .storyEventManager: 4 + 1, .ingredientShared: 4, .menuControls: 2,
        .menuTopicManager: 2 * 3, .tempEffects: 1 + 4 + 1 + 1, .animObjects: 4, .timer: 2 * 4
    ]

    private static func emptyLayout(_ type: ESSGlobalDataType) -> Data {
        // Quest static data: five zero counts, an empty list, and a last byte UESP
        // says is always 1.
        guard type != .questStaticData else { return Data(count: 5 * 4 + 1) + Data([1]) }
        return Data(count: emptySizes[type] ?? 0)
    }
}
