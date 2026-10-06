// Turns a decoded `.ess` into the contents of an OpenSky save: a world state snapshot,
// the clock, and script state, plus a report of what did not map. The app writes the
// contents as an `.osav` and loads it, so there is one restore path.
// See docs/engine/ess-import.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

nonisolated public struct ESSImportResult: Sendable {
    public let contents: OpenSkySaveContents
    public let report: ESSImportReport
    public let placement: ESSImportedPlacement?
}

nonisolated public struct ESSImporter {
    let file: ESSFile
    let records: any ESSImportRecords
    let mapping: ESSLoadOrderMapping
    var report: ESSImportReport
    var components: [ReferenceKey: [WorldStateComponentValue]] = [:]
    var globals: [WorldStateGlobalSnapshotEntry] = []
    var clock: GameClock?
    var scripts: [PapyrusInstanceState] = []
    var placement: ESSImportedPlacement?
    /// Created forms in the order first met, so one save always imports the same keys.
    var createdKeys: [UInt32: ReferenceKey] = [:]

    /// The player's placed reference in `Skyrim.esm`.
    static let playerReference = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x14)

    /// Never throws for a decoded file: every part that does not map is reported.
    public static func run(
        _ file: ESSFile, records: any ESSImportRecords, appVersion: String
    ) -> ESSImportResult {
        var importer = ESSImporter(file: file, records: records)
        importer.importGlobals()
        importer.importPlayer()
        importer.importChangeForms()
        importer.importPapyrus()
        importer.importCreatedObjects()
        return importer.finish(appVersion: appVersion)
    }

    init(file: ESSFile, records: any ESSImportRecords) {
        self.file = file
        self.records = records
        mapping = ESSLoadOrderMapping(file: file, currentPlugins: records.loadOrder)
        report = ESSImportReport(loadOrder: mapping.comparison)
    }

    // MARK: - Keys

    /// The session key of a form, or the reason it has none. A created form gets the
    /// next generated key.
    mutating func key(for ref: ESSRefID) -> Result<ReferenceKey, ESSImportDrop> {
        switch mapping.resolve(ref) {
        case .null:
            return .failure(.null)
        case let .form(form):
            if
                form.plugin.lowercased() == Self.playerReference.plugin.lowercased(),
                form.objectID == Self.playerReference.objectID
            {
                return .success(.player)
            }
            return .success(ReferenceKey(resolved: form))
        case let .created(id):
            if let key = createdKeys[id] {
                return .success(key)
            }
            let key = ReferenceKey.generated(UInt64(createdKeys.count + 1))
            createdKeys[id] = key
            return .success(key)
        case let .unmapped(reason):
            return .failure(.unmapped(reason))
        }
    }

    /// A plugin form of an expected record type, or the reason it is not one.
    func form(
        _ ref: ESSRefID, signature expected: Set<String>
    ) -> Result<ResolvedFormID, ESSImportDrop> {
        switch mapping.resolve(ref) {
        case .null: return .failure(.null)
        case .created: return .failure(.created)
        case let .unmapped(reason): return .failure(.unmapped(reason))
        case let .form(form):
            guard let signature = records.signature(of: form) else {
                return .failure(.missingRecord)
            }
            guard expected.contains(signature) else {
                return .failure(.wrongType(signature))
            }
            return .success(form)
        }
    }

    mutating func add(_ value: some WorldStateComponent, to key: ReferenceKey) {
        components[key, default: []].append(WorldStateComponentValue(value))
    }

    // MARK: - Globals and clock

    mutating func importGlobals() {
        let decoded: [ESSGlobalVariable]
        do {
            decoded = try file.globalVariables()
        } catch {
            report.update("globals") { $0.skip("global variable table: \(error)") }
            return
        }
        var time: [GameClock.TimeGlobal: Float] = [:]
        for global in decoded {
            switch form(global.global, signature: ["GLOB"]) {
            case let .failure(reason):
                report.update("globals") { $0.drop(reason.description) }
            case let .success(form):
                if
                    let editorID = records.editorID(of: form),
                    let timeGlobal = GameClock.TimeGlobal(editorID: editorID)
                {
                    time[timeGlobal] = global.value
                    continue
                }
                guard let type = records.globalType(of: form) else {
                    report.update("globals") { $0.drop("not a global now") }
                    continue
                }
                globals.append(WorldStateGlobalSnapshotEntry(
                    key: ReferenceKey(resolved: form),
                    value: GlobalValue(type: type, rawValue: global.value)
                ))
                report.update("globals") { $0.imported += 1 }
            }
        }
        importClock(time)
    }

    /// `GameDaysPassed` holds the whole date and hour; the calendar globals are the
    /// fallback when it is missing.
    private mutating func importClock(_ time: [GameClock.TimeGlobal: Float]) {
        if let days = time[.gameDaysPassed] {
            var value = GameClock()
            value.setProjectedValue(days, for: .gameDaysPassed)
            clock = value
        } else if
            let year = time[.gameYear], let month = time[.gameMonth],
            let day = time[.gameDay], let hour = time[.gameHour]
        {
            clock = GameClock(year: Int(year), month: Int(month), day: Int(day), hour: hour)
        }
        report.update("clock") { category in
            if clock == nil {
                category.drop("no GameDaysPassed or calendar globals")
            } else {
                category.imported = 1
            }
        }
    }

    // MARK: - Result

    func finish(appVersion: String) -> ESSImportResult {
        let entries = components.keys.sorted().map { key in
            var byKind: [WorldStateComponentKind: WorldStateComponentValue] = [:]
            for value in components[key] ?? [] {
                byKind[value.kind] = value
            }
            return WorldStateSnapshotEntry(key: key, delta: ReferenceStateDelta(components: byKind))
        }
        let snapshot = WorldStateSnapshot(
            entries: entries, nextGeneratedSequence: UInt64(createdKeys.count + 1),
            globals: globals.sorted { $0.key < $1.key }
        )
        let created = file.header.savedAt.map { UInt64(max(0, $0.timeIntervalSince1970)) } ?? 0
        let contents = OpenSkySaveContents(
            snapshot: snapshot,
            metadata: SaveCreationMetadata(creationTimestamp: created, appVersion: appVersion),
            clock: clock,
            scripts: scripts.sorted { $0.key < $1.key },
            summary: ESSSaveFolder.summary(of: file.header),
            thumbnail: ESSSaveFolder.thumbnail(of: file.screenshot)
        )
        return ESSImportResult(contents: contents, report: report, placement: placement)
    }
}

/// Why one decoded value was not brought over.
nonisolated enum ESSImportDrop: Error, Hashable {
    case null
    case created
    case unmapped(ESSUnmappedReason)
    case missingRecord
    case wrongType(String)

    var description: String {
        switch self {
        case .null: "null form"
        case .created: "created form OpenSky cannot create"
        case let .unmapped(reason): reason.description
        case .missingRecord: "form has no record now"
        case let .wrongType(signature): "form is a \(signature) now"
        }
    }
}
