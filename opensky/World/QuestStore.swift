// QUST index (issue #181, roadmap item 13.1).
//
// The plugin side of the quest system, built once from an `ESMFile` and
// immutable afterwards, exactly like `GlobalStore` and `WeatherStore`: only
// value types survive construction, so the index is safe to read from any
// queue. Quest *state* — which quests are running, which stage each one is on
// — is the runtime's (#182) and deliberately does not live here.
//
// Editor-ID lookup is case-insensitive for the same reason globals are: a
// quest is named by scripts and by the console, and Skyrim has always matched
// those without regard to case.
//
// Documented in docs/formats/records.md.

import Foundation

nonisolated final class QuestStore: Sendable {
    /// Raw FormID -> decoded record.
    private let questsByFormID: [UInt32: Quest]
    /// Lowercased editor ID -> raw FormID.
    private let formIDsByEditorID: [String: UInt32]
    /// Raw FormID -> session-stable identity, resolved once through the
    /// plugin's master list so runtime state and saves never key off a
    /// load-order-relative number.
    private let keysByFormID: [UInt32: ReferenceKey]
    /// The inverse of `keysByFormID`, which is what the Papyrus side needs:
    /// a `Quest` native arrives holding a `ReferenceKey` — the identity every
    /// script handle resolves to — and has to name the QUST record behind it
    /// before `QuestRuntime` can be asked anything (issue #322).
    private let formIDsByKey: [ReferenceKey: UInt32]
    /// QUST records in the top group that failed to decode. Zero in vanilla
    /// data; a sweep asserts it rather than silently indexing fewer quests.
    let skippedRecordCount: Int

    static let empty = QuestStore(
        quests: [],
        resolver: FormIDResolver(pluginName: "", masters: [])
    )

    /// - Parameter pluginName: file name of `file`, needed because a plugin
    ///   does not record its own name and `ReferenceKey` is built from it.
    convenience init(file: ESMFile, pluginName: String, localized: Bool? = nil) {
        let header = try? file.pluginHeader()
        let masters = header?.masters ?? []
        let isLocalized = localized ?? (header?.isLocalized ?? false)
        var decoded: [Quest] = []
        var skipped = 0
        if let top = file.topGroup(of: "QUST"), let children = try? top.children() {
            for case let .record(record) in children where record.type == "QUST" {
                guard let quest = try? Quest(record: record, localized: isLocalized) else {
                    skipped += 1
                    continue
                }
                decoded.append(quest)
            }
        }
        self.init(
            quests: decoded,
            resolver: FormIDResolver(pluginName: pluginName, masters: masters),
            skippedRecordCount: skipped
        )
    }

    init(quests: [Quest], resolver: FormIDResolver, skippedRecordCount: Int = 0) {
        var byFormID: [UInt32: Quest] = [:]
        var byEditorID: [String: UInt32] = [:]
        var keys: [UInt32: ReferenceKey] = [:]
        byFormID.reserveCapacity(quests.count)
        for quest in quests {
            byFormID[quest.formID.rawValue] = quest
            if let editorID = quest.editorID, !editorID.isEmpty {
                byEditorID[editorID.lowercased()] = quest.formID.rawValue
            }
            if let key = ReferenceKey.resolve(quest.formID, using: resolver) {
                keys[quest.formID.rawValue] = key
            }
        }
        questsByFormID = byFormID
        formIDsByEditorID = byEditorID
        keysByFormID = keys
        // Built by accumulation rather than by `Dictionary(uniqueKeysWithValues:)`
        // because that traps on a collision, and a plugin listing the same
        // master twice can hand two FormIDs the same key. The lowest FormID
        // wins so the inverse is deterministic whatever the dictionary order.
        var inverse: [ReferenceKey: UInt32] = [:]
        for (raw, key) in keys where raw < (inverse[key] ?? UInt32.max) {
            inverse[key] = raw
        }
        formIDsByKey = inverse
        self.skippedRecordCount = skippedRecordCount
    }

    var count: Int {
        questsByFormID.count
    }

    var isEmpty: Bool {
        questsByFormID.isEmpty
    }

    func quest(_ id: FormID) -> Quest? {
        questsByFormID[id.rawValue]
    }

    func quest(editorID: String) -> Quest? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return questsByFormID[raw]
    }

    func formID(editorID: String) -> FormID? {
        formIDsByEditorID[editorID.lowercased()].map(FormID.init)
    }

    /// Session-stable key for a quest, which is how the runtime layer and the
    /// save file address it. Nil for a FormID this plugin does not define.
    func key(for id: FormID) -> ReferenceKey? {
        keysByFormID[id.rawValue]
    }

    /// FormID behind a session-stable key, the direction the Papyrus natives
    /// read (issue #322). Nil for a key that names no quest this session
    /// loaded.
    func formID(for key: ReferenceKey) -> FormID? {
        formIDsByKey[key].map(FormID.init)
    }

    /// The QUST record a session-stable key names, or nil when it names none.
    func quest(key: ReferenceKey) -> Quest? {
        formIDsByKey[key].flatMap { questsByFormID[$0] }
    }

    func key(editorID: String) -> ReferenceKey? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return keysByFormID[raw]
    }

    /// Records in editor-ID order, for inspection surfaces. Records without an
    /// editor ID sort by FormID under their hex spelling.
    func sortedQuests() -> [Quest] {
        questsByFormID.values.sorted {
            ($0.editorID ?? $0.formID.description) < ($1.editorID ?? $1.formID.description)
        }
    }

    /// Quests that would appear in the journal — everything except type
    /// `none`, which the journal never lists.
    func journalQuests() -> [Quest] {
        sortedQuests().filter { $0.kind != .none }
    }
}
