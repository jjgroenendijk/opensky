// The empty form of every global data table, laid out as UESP documents each table
// with its counts at zero. See docs/formats/ess.md#global-data-tables and #writing.

import Foundation

nonisolated public enum ESSEmptyTable {
    /// The table with every count at zero and every unknown field zero. Types 104
    /// and 1004 have no documented layout and are written with no bytes.
    public static func table(_ type: ESSGlobalDataType) throws(ESSError) -> ESSGlobalData {
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
            return ESSGlobalData(type: type.rawValue, data: emptyLayout(type))
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
