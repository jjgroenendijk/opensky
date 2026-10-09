// FormID lookup over a whole load order, numbered as the game numbers forms at
// runtime. The last plugin that holds a record wins, and a later plugin can add
// references to a cell another plugin defines. Rules: docs/formats/formid.md.

import Foundation
import OpenSkyFormatsCore

/// One plugin's record, with the translation into the load-order space.
nonisolated public struct LoadOrderRecord: Sendable {
    public let record: ESMRecord
    /// Position of the record's plugin in the load order; 0 is the first plugin.
    public let position: Int
    public let translation: FormIDTranslation
    /// The TES4 localized flag of the plugin that holds the record.
    public let localized: Bool

    /// The record's own FormID in the load-order space.
    public var formID: FormID {
        translation(FormID(record.formID))
    }

    /// Decodes the record and moves its FormIDs into the load-order space.
    public func decode<Value: FormIDRenumbering>(
        _ decode: (ESMRecord) throws -> Value
    ) rethrows -> Value {
        try translation.renumber(decode(record))
    }
}

/// A REFR or ACHR stored under a cell, and the children group it came from.
nonisolated public struct CellChildRecord: Sendable {
    public let record: LoadOrderRecord
    public let isPersistent: Bool
}

/// One active plugin and the translation of its FormIDs into the load-order space.
nonisolated public struct LoadOrderPlugin: Sendable {
    public let name: String
    public let file: ESMFile
    public let translation: FormIDTranslation
}

nonisolated public struct LoadOrderRecordIndex: Sendable {
    private struct Source: Sendable {
        let position: Int
        let index: ESMFormIDIndex
        let translation: FormIDTranslation
        let localized: Bool
        /// Keyed by the load-order FormID of the owning CELL.
        let cellChildren: [UInt32: [CellChildRecord]]
    }

    /// The FormID space every lookup takes and returns.
    public let space: FormIDResolver
    /// Lowest priority first.
    public let plugins: [LoadOrderPlugin]
    private let sources: [Source]

    /// The first plugin's cells are read through its own groups, so only the later
    /// plugins get a children table.
    ///
    /// - Parameter space: the target space; the load order of `plugins` when nil.
    ///   A one-plugin builder passes the plugin's own space, so nothing moves.
    public init(plugins: [(name: String, file: ESMFile)], space: FormIDResolver? = nil) {
        let space = space ?? FormIDResolver.loadOrder(plugins.map(\.name))
        self.space = space
        var skipped = SkippedRecords()
        self.plugins = plugins.map { plugin in
            let resolver = FormIDResolver(
                pluginName: plugin.name, masters: skipped.masters(of: plugin.file)
            )
            return LoadOrderPlugin(
                name: plugin.name,
                file: plugin.file,
                translation: FormIDTranslation(source: resolver, target: space)
            )
        }
        sources = self.plugins.enumerated().map { position, plugin in
            let translation = plugin.translation
            let localized = plugin.file.isLocalized
            let isBase = position == 0
            return Source(
                position: position,
                index: ESMFormIDIndex(file: plugin.file),
                translation: translation,
                localized: localized,
                cellChildren: isBase ? [:] : Self.cellChildren(
                    of: plugin.file, position: position, translation: translation,
                    localized: localized
                )
            )
        }
    }

    /// The winning record: the one in the last plugin that holds `formID`. A
    /// deleted record still wins, so the caller decides what deletion means.
    public func record(withFormID formID: FormID) -> LoadOrderRecord? {
        winner(of: formID).map(\.record)
    }

    /// The load-order FormID of the CELL that holds the winning record.
    public func cellFormID(containing formID: FormID) -> FormID? {
        guard
            let found = winner(of: formID),
            let cell = found.source.index.cellFormID(containing: found.local.rawValue)
        else { return nil }
        return found.source.translation(FormID(cell))
    }

    /// The REFR and ACHR records the plugins after the first store under `cell`,
    /// lowest priority first. A later record with the same FormID overrides.
    public func laterChildren(ofCell cell: FormID) -> [CellChildRecord] {
        sources.flatMap { $0.cellChildren[cell.rawValue] ?? [] }
    }

    private struct Winner {
        let record: LoadOrderRecord
        let source: Source
        let local: FormID
    }

    private func winner(of formID: FormID) -> Winner? {
        guard let resolved = space.resolve(formID) else { return nil }
        for source in sources.reversed() {
            guard
                let local = source.translation.source.localFormID(of: resolved),
                let record = source.index.record(withFormID: local.rawValue)
            else { continue }
            let found = LoadOrderRecord(
                record: record, position: source.position, translation: source.translation,
                localized: source.localized
            )
            return Winner(record: found, source: source, local: local)
        }
        return nil
    }

    private struct ChildContext {
        let position: Int
        let translation: FormIDTranslation
        let localized: Bool
    }

    private static func cellChildren(
        of file: ESMFile,
        position: Int,
        translation: FormIDTranslation,
        localized: Bool
    ) -> [UInt32: [CellChildRecord]] {
        let context = ChildContext(
            position: position, translation: translation, localized: localized
        )
        var children: [UInt32: [CellChildRecord]] = [:]
        for type: FourCC in ["CELL", "WRLD"] {
            guard let top = file.topGroup(of: type) else { continue }
            collect(top, context: context, into: &children)
        }
        return children
    }

    /// A malformed group is skipped, as in `ESMWalk`.
    private static func collect(
        _ group: ESMGroup,
        context: ChildContext,
        into children: inout [UInt32: [CellChildRecord]]
    ) {
        guard let items = try? group.children() else { return }
        let isPersistent = group.kind == .cellPersistentChildren
        let ownsRecords = isPersistent || group.kind == .cellTemporaryChildren
        for item in items {
            switch item {
            case let .record(record)
                where ownsRecords && (record.type == "REFR" || record.type == "ACHR"):
                let cell = context.translation(FormID(group.header.label)).rawValue
                let found = LoadOrderRecord(
                    record: record, position: context.position,
                    translation: context.translation, localized: context.localized
                )
                children[cell, default: []].append(
                    CellChildRecord(record: found, isPersistent: isPersistent)
                )
            case let .group(nested):
                collect(nested, context: context, into: &children)
            case .record:
                continue
            }
        }
    }
}
