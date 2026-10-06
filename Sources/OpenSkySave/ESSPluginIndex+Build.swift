// Builds an `ESSPluginIndex` for one save with a header-only walk of each plugin. Cell
// children are walked only when the save changed an inventory, and only those
// references decode their base.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyFormatsPEX
import OpenSkyGameData

nonisolated extension ESSPluginIndex {
    /// The record types the import checks a form against.
    static let indexedTypes: Set<FourCC> = [
        "GLOB", "QUST", "INFO", "RACE", "SPEL", "FACT", "CELL", "WRLD", "CONT", "NPC_"
    ]
    private static let walkedTopGroups = indexedTypes.union(["DIAL"])

    /// Reads the installed load order and scripts under `root`.
    @concurrent
    public static func load(for file: ESSFile, root: GameDataRoot) async -> ESSPluginIndex {
        build(
            for: file, plugins: ActivePluginFiles.load(root: root),
            scripts: PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        )
    }

    public static func build(
        for file: ESSFile, plugins: [(name: String, file: ESMFile)], scripts: PexScriptLoader? = nil
    ) -> ESSPluginIndex {
        var records = ESSPluginIndex(loadOrder: plugins.map(\.name))
        let wanted = changedInventories(in: file, loadOrder: records.loadOrder)
        for plugin in plugins {
            guard let header = try? plugin.file.pluginHeader() else { continue }
            var walk = Walk(
                resolver: header.formIDResolver(pluginName: plugin.name), wanted: wanted
            )
            for group in plugin.file.topGroups {
                guard let type = group.recordType, walkedTopGroups.contains(type) else { continue }
                walk.visit(group, exterior: false)
            }
            records.forms.merge(walk.forms) { _, later in later }
            records.referenceBases.merge(walk.bases) { _, later in later }
        }
        if let scripts, let papyrus = try? file.papyrus() {
            for script in papyrus.scripts {
                records.loadScript(script.name, from: scripts)
            }
        }
        return records
    }

    private static func changedInventories(in file: ESSFile, loadOrder: [String]) -> Set<Key> {
        let mapping = ESSLoadOrderMapping(file: file, currentPlugins: loadOrder)
        var wanted: Set<Key> = []
        for change in file.changeForms where change.type?.isReference == true {
            guard
                change.has(ESSChangeFlag.Reference.inventory),
                case let .form(form) = mapping.resolve(change.form)
            else { continue }
            wanted.insert(Key(form))
        }
        return wanted
    }

    /// The script's own variables and every parent's, keyed the way the VM keys them.
    private mutating func loadScript(_ name: String, from loader: PexScriptLoader) {
        var declared: [String: String] = [:]
        var next: String? = name
        var depth = 0
        while let current = next, !current.isEmpty, depth < 32 {
            guard let object = (try? loader.load(current))?.objects.first else { break }
            let owner = current.lowercased()
            for variable in object.variables {
                declared[variable.name.lowercased()] = declared[variable.name.lowercased()] ?? owner
            }
            next = object.parentClassName
            depth += 1
        }
        scriptVariables[name.lowercased()] = declared.isEmpty ? nil : declared
    }
}

nonisolated private struct Walk {
    let resolver: FormIDResolver
    let wanted: Set<ESSPluginIndex.Key>
    var forms: [ESSPluginIndex.Key: ESSPluginIndex.Form] = [:]
    var bases: [ESSPluginIndex.Key: ResolvedFormID] = [:]

    private static let cellChildKinds: Set<ESMGroup.Kind> = [
        .cellChildren, .cellPersistentChildren, .cellTemporaryChildren
    ]

    mutating func visit(_ group: ESMGroup, exterior: Bool) {
        guard let children = try? group.children() else { return }
        let isCellChildren = group.kind.map(Self.cellChildKinds.contains) ?? false
        if isCellChildren, wanted.isEmpty {
            return
        }
        let inWorld = exterior || group.kind == .worldChildren
        for child in children {
            switch child {
            case let .group(sub): visit(sub, exterior: inWorld)
            case let .record(record) where isCellChildren: noteReference(record)
            case let .record(record): note(record, exterior: inWorld)
            }
        }
    }

    private mutating func note(_ record: ESMRecord, exterior: Bool) {
        guard
            ESSPluginIndex.indexedTypes.contains(record.type), !record.isDeleted,
            let id = resolver.resolve(FormID(record.formID))
        else { return }
        var form = ESSPluginIndex.Form(signature: record.type)
        if record.type == "GLOB", let global = try? Global(record: record) {
            form.editorID = global.editorID
            form.globalType = global.valueType
        } else if
            record.type == "RACE" || record
                .type == "WRLD" || (record.type == "CELL" && !exterior)
        {
            form.editorID = ESMWalk.editorID(of: record)
        }
        form.isExteriorCell = record.type == "CELL" && exterior
        forms[ESSPluginIndex.Key(id)] = form
    }

    private mutating func noteReference(_ record: ESMRecord) {
        guard
            let id = resolver.resolve(FormID(record.formID)),
            wanted.contains(ESSPluginIndex.Key(id)),
            let fields = try? record.fields(),
            let name = fields.first(where: { $0.type == "NAME" }), name.data.count >= 4
        else { return }
        var reader = BinaryReader(name.data)
        guard
            let raw = try? reader.readUInt32(),
            let base = resolver.resolve(FormID(raw)) else { return }
        bases[ESSPluginIndex.Key(id)] = base
    }
}
