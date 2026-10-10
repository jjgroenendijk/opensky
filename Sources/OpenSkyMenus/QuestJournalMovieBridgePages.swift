// The rest of the journal movie's contract: the Quests page flags, the two calls
// it makes to the engine (track a quest, show a target on the map), and the
// Stats page rows. Measured with `openskycli swf action-list --movie
// quest_journal.swf`; see docs/engine/journal.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyQuestsInterface

/// One Stats page row.
nonisolated public struct JournalStatRow: Equatable, Sendable {
    public let name: String
    public let value: Int32
    public let category: MiscStatCategory

    public init(name: String, value: Int32, category: MiscStatCategory) {
        self.name = name
        self.value = value
        self.category = category
    }

    /// Every listed stat in the catalog's order, 0 when never counted.
    public static func rows(_ stats: MiscStatsState) -> [JournalStatRow] {
        MiscStats.catalog.filter(\.isListed).map {
            JournalStatRow(name: $0.name, value: stats.value($0.name), category: $0.category)
        }
    }
}

nonisolated extension QuestJournalMovieBridge {
    public static let statsPagePath = "\(menuPath)/StatsFader/Page_mc"
    public static let toggleTrackingCall = "ToggleQuestActiveStatus"
    public static let showOnMapCall = "ShowTargetOnMap"

    /// `bHasMiscQuests` says a misc row ends the list; `bAllowShowOnMap` enables
    /// the "Show on map" button.
    public static func publishPageFlags(_ model: JournalMenuModel, runtime: SWFMovieRuntime) {
        guard let page = runtime.node(atPath: pagePath, from: runtime.root) else {
            runtime.runtime.noteMissing(pagePath)
            return
        }
        let hasMisc = model.active.contains(where: \.isMiscGroup)
        page.object.assign(.boolean(hasMisc), for: "bHasMiscQuests")
        page.object.assign(.boolean(true), for: "bAllowShowOnMap")
    }

    /// Quest FormID in the high bits, objective index in the low 16. An AS2 number
    /// holds 53 bits exactly, so both survive the round trip.
    public static func questTargetID(_ objective: JournalObjectiveEntry) -> Double {
        Double(UInt64(objective.quest.rawValue) << 16 | UInt64(objective.index))
    }

    public static func objectiveTarget(
        fromID value: AS2Value?
    ) -> (quest: FormID, objective: UInt16)? {
        guard
            case let .number(number) = value, number >= 0, number < 0x1_0000_0000_0000,
            number == number.rounded()
        else { return nil }
        let raw = UInt64(number)
        return (FormID(UInt32(raw >> 16)), UInt16(raw & 0xFFFF))
    }

    /// The movie asks to flip the selected quest; the answer is its new state, which
    /// the movie writes into the row's `active`.
    public static func registerCalls(
        runtime: SWFMovieRuntime,
        toggleTracking: @escaping @MainActor @Sendable (FormID) -> Bool?,
        showOnMap: @escaping @MainActor @Sendable (FormID, UInt16) -> Void
    ) {
        runtime.registerHostFunction(toggleTrackingCall) { call in
            guard
                case let .number(number) = call.arguments.first,
                number >= 0, number <= Double(UInt32.max)
            else { return .undefined }
            let tracked = MainActor.assumeIsolated { toggleTracking(FormID(UInt32(number))) }
            return tracked.map(AS2Value.boolean) ?? .undefined
        }
        runtime.registerHostFunction(showOnMapCall) { call in
            guard let target = objectiveTarget(fromID: call.arguments.first) else {
                return .undefined
            }
            MainActor.assumeIsolated { showOnMap(target.quest, target.objective) }
            return .undefined
        }
    }

    /// `PopulateStatsList` reads its arguments in fours: the name without its `$`,
    /// the value, the category index, and one the page does not read. It appends,
    /// so it runs once per open; `bUpdated` stops the page asking again.
    public static func publishStats(_ rows: [JournalStatRow], runtime: SWFMovieRuntime) {
        guard let page = runtime.node(atPath: statsPagePath, from: runtime.root) else {
            runtime.runtime.noteMissing(statsPagePath)
            return
        }
        let arguments = rows.flatMap { row -> [AS2Value] in
            [
                .string(row.name), .integer(Int(row.value)),
                .integer(row.category.rawValue), .integer(0)
            ]
        }
        runtime.callMovie("PopulateStatsList", atPath: statsPagePath, arguments: arguments)
        page.object.assign(.boolean(true), for: "bUpdated")
    }
}
