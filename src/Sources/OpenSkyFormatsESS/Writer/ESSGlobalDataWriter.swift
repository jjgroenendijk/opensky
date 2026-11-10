// Global data tables on the write side, for the decoded tables.
// See docs/formats/ess.md#global-data-tables and #writing.

import Foundation

nonisolated extension ESSMiscStat {
    static func table(_ stats: [Self]) throws(ESSError) -> ESSGlobalData {
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
}
