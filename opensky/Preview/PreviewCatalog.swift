// Browse catalog for the asset preview GUI (todo 2.10): every archive entry
// plus every plugin record flattened into filterable sidebar rows. AppKit-free
// so grouping + filtering unit-test without a window (openskypreview owns the
// UI, openskyTests exercises this). See docs/tools/preview-gui.md.

import Foundation

/// What one sidebar row selects.
nonisolated enum PreviewSelection {
    case file(VFSEntry)
    case record(ESMRecord)
}

/// One sidebar row. `searchKey` is the lowercase haystack the filter matches
/// (files: the canonical VFS key itself; records: lowercased display text).
nonisolated struct PreviewItem {
    let display: String
    let searchKey: String
    let selection: PreviewSelection
}

nonisolated enum PreviewCategory: CaseIterable {
    case meshes
    case textures
    case records
    case allFiles

    var title: String {
        switch self {
        case .meshes: "Meshes (.nif)"
        case .textures: "Textures (.dds)"
        case .records: "Records (Skyrim.esm)"
        case .allFiles: "All files"
        }
    }
}

nonisolated struct PreviewCatalog {
    let fileCount: Int
    let recordCount: Int
    /// Load problems worth surfacing in the UI (missing esm, ...).
    let notes: [String]

    private let meshes: [PreviewItem]
    private let textures: [PreviewItem]
    private let records: [PreviewItem]
    private let allFiles: [PreviewItem]

    init(files: [VFSEntry], records: [ESMRecord], notes: [String] = []) {
        // Display and search key share one string (VFS keys are already
        // canonical lowercase), so file rows cost one allocation each.
        let fileItems = files.map { entry in
            PreviewItem(display: entry.path, searchKey: entry.path, selection: .file(entry))
        }
        allFiles = fileItems
        meshes = fileItems.filter { $0.searchKey.hasSuffix(".nif") }
        textures = fileItems.filter { $0.searchKey.hasSuffix(".dds") }
        self.records = records.map { record in
            let display = Self.recordDisplay(record)
            return PreviewItem(
                display: display,
                searchKey: display.lowercased(),
                selection: .record(record)
            )
        }
        fileCount = files.count
        recordCount = records.count
        self.notes = notes
    }

    /// "STAT 0001A2B3" — record type + zero-padded hex FormID.
    static func recordDisplay(_ record: ESMRecord) -> String {
        "\(record.type) \(FormID(record.formID))"
    }

    func items(for category: PreviewCategory) -> [PreviewItem] {
        switch category {
        case .meshes: meshes
        case .textures: textures
        case .records: records
        case .allFiles: allFiles
        }
    }

    /// Case-insensitive substring filter; "/" in the query matches the
    /// canonical "\" separator so either spelling finds a path. Empty or
    /// whitespace query -> everything.
    static func filter(_ items: [PreviewItem], query: String) -> [PreviewItem] {
        let needle = query.lowercased()
            .replacingOccurrences(of: "/", with: "\\")
            .trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return items }
        return items.filter { $0.searchKey.contains(needle) }
    }

    /// Loads the whole browse surface: archive enumeration (opens every
    /// archive — seconds on a full install; callers run this off the main
    /// thread) plus a headers-only walk of every Skyrim.esm record. A
    /// missing/unreadable esm degrades to file browsing with a note, never
    /// a crash. Returns the plugin's localized flag for record decoding.
    static func load(
        fileSystem: VirtualFileSystem,
        esmURL: URL
    ) -> (catalog: PreviewCatalog, localized: Bool) {
        let files = fileSystem.archiveEntries()
        do {
            let file = try ESMFile(url: esmURL)
            var records: [ESMRecord] = []
            ESMWalk.forEachRecord(in: file) { record in
                records.append(record)
                return true
            }
            let localized = (try? file.pluginHeader())?.isLocalized ?? false
            return (PreviewCatalog(files: files, records: records), localized)
        } catch {
            let note = "Skyrim.esm unavailable: \(String(describing: error))"
            return (PreviewCatalog(files: files, records: [], notes: [note]), false)
        }
    }
}
