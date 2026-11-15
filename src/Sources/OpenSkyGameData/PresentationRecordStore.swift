// The load-order records behind cameras, combat styles, messages, and body parts:
// CAMS and CPTH, CSTY, MESG, LSCR with the STAT models loading screens show, and
// BPTD. Built once off one `RecordIndex`; a STAT decodes only when a loading screen
// shows it. See docs/formats/camera-records.md,
// combat-style.md, messages.md, and body-parts.md.

import Foundation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public struct PresentationRecordStore: Sendable {
    public static let recordTypes: Set<FourCC> = CameraPathStore.types
        .union(["CSTY", "MESG", "LSCR", "STAT", "BPTD"])

    public let cameras: CameraPathStore
    public let combatStyles: TypedRecordStore<CombatStyle>
    public let messages: TypedRecordStore<GameMessage>
    public let loadScreens: TypedRecordStore<LoadScreen>
    /// The index the STAT records are read from, one at a time, for a loading screen's
    /// `NNAM` object. Skyrim.esm holds tens of thousands of STATs and loading screens
    /// name a few hundred.
    private let index: RecordIndex
    /// The hit, sever, and explode parts a race's `GNAM` names.
    public let bodyParts: TypedRecordStore<BodyPartData>

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
        self.index = index
        bodyParts = TypedRecordStore(
            index: index, types: ["BPTD"],
            decode: { try BodyPartData(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.recordTypes))
    }

    /// The model path a loading screen shows, or nil when its STAT is missing.
    public func model(of screen: ResolvedRecord<LoadScreen>) -> String? {
        guard
            let id = index.resolvedID(screen.record.model, fromPlugin: screen.sourcePlugin),
            case let .decoded(path, _) = index.decodeIndexed(id, using: {
                try Self.modelPath(of: $0.record)
            })
        else { return nil }
        return path
    }

    private static func modelPath(of record: ESMRecord) throws -> String {
        var fields = try RecordFields(record: record, type: "STAT")
        return fields.model()?.path ?? ""
    }
}
