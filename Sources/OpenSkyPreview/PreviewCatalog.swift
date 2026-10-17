// Browse catalog for the main app's asset browser: every archive entry
// plus every plugin record flattened into filterable sidebar rows. AppKit-free
// so grouping + filtering unit-test without a window (main app owns the UI,
// OpenSkyTests exercises this). See docs/tools/preview-gui.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// What one sidebar row selects.
nonisolated public enum PreviewSelection: Sendable {
    case file(VFSEntry)
    case record(PreviewRecord)
}

/// Record plus the plugin metadata needed to resolve its file-relative links.
nonisolated public struct PreviewRecord: Sendable {
    public let record: ESMRecord
    public let sourcePlugin: String
    public let localized: Bool
    public let resolvedID: ResolvedFormID?

    public init(
        record: ESMRecord,
        sourcePlugin: String,
        localized: Bool,
        resolvedID: ResolvedFormID?
    ) {
        self.record = record
        self.sourcePlugin = sourcePlugin
        self.localized = localized
        self.resolvedID = resolvedID
    }
}

/// One sidebar row. `searchKey` is the lowercase haystack the filter matches
/// (files: the canonical VFS key itself; records: lowercased display text).
nonisolated public struct PreviewItem: Sendable {
    public let display: String
    public let searchKey: String
    public let selection: PreviewSelection
}

nonisolated public enum PreviewCategory: CaseIterable, Sendable {
    case meshes
    case textures
    case records
    case referenceRecords
    case allFiles

    public var title: String {
        switch self {
        case .meshes: "Meshes (.nif)"
        case .textures: "Textures (.dds)"
        case .records: "Records (every plugin)"
        case .referenceRecords: "Reference records (load order)"
        case .allFiles: "All files"
        }
    }
}

nonisolated public struct PreviewCatalog: Sendable {
    public let fileCount: Int
    public let recordCount: Int
    /// Load problems worth surfacing in the UI (missing esm, ...).
    public let notes: [String]

    private let meshes: [PreviewItem]
    private let textures: [PreviewItem]
    private let records: [PreviewItem]
    private let allFiles: [PreviewItem]

    /// One plugin's records, as a synthetic test fixture lists them.
    public init(
        files: [VFSEntry],
        records: [ESMRecord],
        recordSourcePlugin: String = "Skyrim.esm",
        recordsLocalized: Bool = false,
        notes: [String] = []
    ) {
        let rows = records.map { record in
            let display = Self.recordDisplay(record)
            return PreviewItem(
                display: display,
                searchKey: display.lowercased(),
                selection: .record(PreviewRecord(
                    record: record,
                    sourcePlugin: recordSourcePlugin,
                    localized: recordsLocalized,
                    resolvedID: nil
                ))
            )
        }
        self.init(files: files, recordRows: rows, notes: notes)
    }

    /// Every record of every plugin, each under its load-order FormID and plugin,
    /// so an override shows beside the record it replaces.
    public init(files: [VFSEntry], loadOrder: LoadOrderPlugins, notes: [String] = []) {
        var rows: [PreviewItem] = []
        for plugin in loadOrder.plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                let formID = plugin.formID(of: record)
                let display = "\(record.type) \(formID) \(plugin.name)"
                rows.append(PreviewItem(
                    display: display,
                    searchKey: display.lowercased(),
                    selection: .record(PreviewRecord(
                        record: record,
                        sourcePlugin: plugin.name,
                        localized: plugin.localized,
                        resolvedID: loadOrder.space.resolve(formID)
                    ))
                ))
                return true
            }
        }
        self.init(files: files, recordRows: rows, notes: notes)
    }

    private init(files: [VFSEntry], recordRows: [PreviewItem], notes: [String]) {
        // Display and search key share one string (VFS keys are already
        // canonical lowercase), so file rows cost one allocation each.
        let fileItems = files.map { entry in
            PreviewItem(display: entry.path, searchKey: entry.path, selection: .file(entry))
        }
        allFiles = fileItems
        meshes = fileItems.filter { $0.searchKey.hasSuffix(".nif") }
        textures = fileItems.filter { $0.searchKey.hasSuffix(".dds") }
        records = recordRows
        fileCount = files.count
        recordCount = recordRows.count
        self.notes = notes
    }

    /// "STAT 0001A2B3" — record type + zero-padded hex FormID.
    public static func recordDisplay(_ record: ESMRecord) -> String {
        "\(record.type) \(FormID(record.formID))"
    }

    public func items(for category: PreviewCategory) -> [PreviewItem] {
        switch category {
        case .meshes: meshes
        case .textures: textures
        case .records: records
        case .referenceRecords: []
        case .allFiles: allFiles
        }
    }

    /// Case-insensitive substring filter; "/" in the query matches the
    /// canonical "\" separator so either spelling finds a path. Empty or
    /// whitespace query -> everything.
    public static func filter(_ items: [PreviewItem], query: String) -> [PreviewItem] {
        let needle = query.lowercased()
            .replacingOccurrences(of: "/", with: "\\")
            .trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return items }
        return items.filter { $0.searchKey.contains(needle) }
    }

    /// Loads the whole browse surface: archive enumeration (opens every
    /// archive — seconds on a full install; callers run this off the main
    /// thread) plus a headers-only walk of every plugin's records. A load order
    /// that did not open degrades to file browsing with a note, never a crash.
    public static func load(
        fileSystem: any GameFileSource,
        loadOrder: Result<LoadOrderPlugins, any Error>
    ) -> PreviewCatalog {
        let files = fileSystem.archiveEntries()
        switch loadOrder {
        case let .success(plugins):
            return PreviewCatalog(files: files, loadOrder: plugins)
        case let .failure(error):
            let note = "Plugins unavailable: \(String(describing: error))"
            return PreviewCatalog(files: files, records: [], notes: [note])
        }
    }
}
