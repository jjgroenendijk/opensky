// The load-order records behind cameras, combat styles, and messages: CAMS and
// CPTH, CSTY, MESG, and LSCR with the STAT models loading screens show.
// Built once off one `RecordIndex`. See docs/formats/camera-records.md,
// combat-style.md, and messages.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct PresentationRecordStore: Sendable {
    public static let recordTypes: Set<FourCC> = CameraPathStore.types
        .union(["CSTY", "MESG", "LSCR", "STAT"])

    public let cameras: CameraPathStore
    public let combatStyles: TypedRecordStore<CombatStyle>
    public let messages: TypedRecordStore<GameMessage>
    public let loadScreens: TypedRecordStore<LoadScreen>
    /// The `MODL` path of each STAT, for a loading screen's `NNAM` object.
    public let staticModels: TypedRecordStore<String>

    public init(index: RecordIndex) {
        cameras = CameraPathStore(index: index)
        combatStyles = TypedRecordStore(
            index: index, types: ["CSTY"],
            decode: { try CombatStyle(record: $0.record) }, editorID: \.editorID
        )
        messages = TypedRecordStore(
            index: index, types: ["MESG"],
            decode: { try GameMessage(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        loadScreens = TypedRecordStore(
            index: index, types: ["LSCR"],
            decode: { try LoadScreen(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        staticModels = TypedRecordStore(
            index: index, types: ["STAT"],
            decode: { try Self.modelPath(of: $0.record) }, editorID: { _ in nil }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.recordTypes))
    }

    /// The model path a loading screen shows, or nil when its STAT is missing.
    public func model(of screen: ResolvedRecord<LoadScreen>) -> String? {
        staticModels.resolve(screen.record.model, fromPlugin: screen.sourcePlugin)?.record
    }

    private static func modelPath(of record: ESMRecord) throws -> String {
        var fields = try RecordFields(record: record, type: "STAT")
        return fields.model()?.path ?? ""
    }
}
