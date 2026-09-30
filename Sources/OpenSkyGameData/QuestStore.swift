// QUST index for one plugin, immutable after construction. Quest state lives
// in the runtime, not here. Editor-ID lookup ignores case, as scripts and the
// console do (docs/formats/quest-records.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public final class QuestStore: Sendable {
    /// Raw FormID -> decoded record.
    private let questsByFormID: [UInt32: Quest]
    /// Lowercased editor ID -> raw FormID.
    private let formIDsByEditorID: [String: UInt32]
    /// Raw FormID -> session-stable identity, resolved once through the
    /// plugin's master list so runtime state and saves never key off a
    /// load-order-relative number.
    private let keysByFormID: [UInt32: ReferenceKey]
    /// The inverse of `keysByFormID`: a Papyrus `Quest` native holds a
    /// `ReferenceKey` and needs the QUST record behind it.
    private let formIDsByKey: [ReferenceKey: UInt32]
    /// Master-list resolver of the source plugin. Alias filling resolves the
    /// FormIDs the QUST records point at, such as an ALFR reference.
    public let resolver: FormIDResolver
    /// QUST records in the top group that failed to decode. Zero in vanilla data.
    public let skippedRecords: SkippedRecords

    public var skippedRecordCount: Int {
        skippedRecords.total
    }

    public static let empty = QuestStore(
        quests: [],
        resolver: FormIDResolver(pluginName: "", masters: [])
    )

    /// - Parameter pluginName: file name of `file`, needed because a plugin
    ///   does not record its own name and `ReferenceKey` is built from it.
    public convenience init(file: ESMFile, pluginName: String, localized: Bool? = nil) {
        let isLocalized = localized ?? file.isLocalized
        var decoded: [Quest] = []
        var skipped = SkippedRecords()
        let masters = skipped.masters(of: file)
        if let top = file.topGroup(of: "QUST") {
            for case let .record(record) in skipped.children(of: top) where record.type == "QUST" {
                let quest = skipped.decode(record) { try Quest(record: $0, localized: isLocalized) }
                decoded.append(contentsOf: quest.map { [$0] } ?? [])
            }
        }
        self.init(
            quests: decoded,
            resolver: FormIDResolver(pluginName: pluginName, masters: masters),
            skippedRecords: skipped
        )
    }

    public init(
        quests: [Quest],
        resolver: FormIDResolver,
        skippedRecords: SkippedRecords = SkippedRecords()
    ) {
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
        self.resolver = resolver
        self.skippedRecords = skippedRecords
    }

    public var count: Int {
        questsByFormID.count
    }

    public var isEmpty: Bool {
        questsByFormID.isEmpty
    }

    public func quest(_ id: FormID) -> Quest? {
        questsByFormID[id.rawValue]
    }

    public func quest(editorID: String) -> Quest? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return questsByFormID[raw]
    }

    public func formID(editorID: String) -> FormID? {
        formIDsByEditorID[editorID.lowercased()].map(FormID.init)
    }

    /// Session-stable key for a quest, which is how the runtime layer and the
    /// save file address it. Nil for a FormID this plugin does not define.
    public func key(for id: FormID) -> ReferenceKey? {
        keysByFormID[id.rawValue]
    }

    /// FormID behind a session-stable key, the direction the Papyrus natives
    /// read. Nil for a key that names no loaded quest.
    public func formID(for key: ReferenceKey) -> FormID? {
        formIDsByKey[key].map(FormID.init)
    }

    /// The QUST record a session-stable key names, or nil when it names none.
    public func quest(key: ReferenceKey) -> Quest? {
        formIDsByKey[key].flatMap { questsByFormID[$0] }
    }

    public func key(editorID: String) -> ReferenceKey? {
        guard let raw = formIDsByEditorID[editorID.lowercased()] else { return nil }
        return keysByFormID[raw]
    }

    /// Records in editor-ID order, for inspection surfaces. Records without an
    /// editor ID sort by FormID under their hex spelling.
    public func sortedQuests() -> [Quest] {
        questsByFormID.values.sorted {
            ($0.editorID ?? $0.formID.description) < ($1.editorID ?? $1.formID.description)
        }
    }

    /// Quests that would appear in the journal — everything except type
    /// `none`, which the journal never lists.
    public func journalQuests() -> [Quest] {
        sortedQuests().filter { $0.kind != .none }
    }
}
