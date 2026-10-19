// The installed plugins as an `ESSExportRecords`. The index for an export walks the
// placed references the session changed, and loads the scripts its state names.
// See docs/engine/ess-export.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsPEX
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

nonisolated extension ESSPluginIndex {
    @concurrent
    public static func load(
        forExport contents: OpenSkySaveContents, root: GameDataRoot
    ) async -> ESSPluginIndex {
        build(
            forExport: contents, plugins: ActivePluginFiles.load(root: root),
            scripts: PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        )
    }

    public static func build(
        forExport contents: OpenSkySaveContents, plugins: [(name: String, file: ESMFile)],
        scripts: PexScriptLoader? = nil
    ) -> ESSPluginIndex {
        var records = ESSPluginIndex(loadOrder: plugins.map(\.name), light: lightNames(plugins))
        records.walk(plugins, wanted: changedReferences(in: contents.snapshot))
        if let scripts {
            for state in contents.scripts {
                records.loadExportScript(state.key.scriptName, from: scripts)
            }
        }
        return records
    }

    /// Plugin references with state, and the references alias fills point at.
    private static func changedReferences(in snapshot: WorldStateSnapshot) -> Set<Key> {
        var keys: [ReferenceKey] = []
        for entry in snapshot.entries {
            keys.append(entry.key)
            let fills = entry.delta.component(QuestAliasState.self)?.fills ?? []
            keys.append(contentsOf: fills.map(\.reference))
        }
        var wanted: Set<Key> = []
        for case let .plugin(name, objectID) in keys {
            wanted.insert(Key(ResolvedFormID(plugin: name, objectID: objectID)))
        }
        return wanted
    }

    private mutating func loadExportScript(_ name: String, from loader: PexScriptLoader) {
        var next = name
        var depth = 0
        while !next.isEmpty, depth < 32, exportScripts[next.lowercased()] == nil {
            guard let object = (try? loader.load(next))?.objects.first else { return }
            let variables = object.variables.map { variable in
                ESSExportScript.Variable(
                    name: variable.name, typeName: variable.typeName,
                    initial: Self.initialValue(variable.initialValue)
                )
            }
            exportScripts[next.lowercased()] = ESSExportScript(
                name: next, parent: object.parentClassName, variables: variables
            )
            next = object.parentClassName
            depth += 1
        }
    }

    private static func initialValue(_ value: PexValue) -> PapyrusValue {
        switch value {
        case .null, .identifier: .none
        case let .string(text): .string(text)
        case let .integer(number): .integer(number)
        case let .float(number): .float(number)
        case let .boolean(flag): .boolean(flag)
        }
    }
}

nonisolated extension ESSPluginRecords: ESSExportRecords {
    public var plugins: [ESSExportPlugin] {
        index.loadOrder.map {
            ESSExportPlugin(name: $0, isLight: index.lightPlugins.contains($0.lowercased()))
        }
    }

    public func form(editorID: String, signature: String) -> ResolvedFormID? {
        let wanted = editorID.lowercased()
        let match = index.forms.first { _, form in
            String(describing: form.signature) == signature
                && form.editorID?.lowercased() == wanted
        }
        return match.map {
            ResolvedFormID(plugin: index.canonicalName($0.key.plugin), objectID: $0.key.objectID)
        }
    }

    public func recordFlags(of reference: ResolvedFormID) -> UInt32? {
        index.placedReferences[ESSPluginIndex.Key(reference)]?.flags
    }

    public func placementSpace(of reference: ResolvedFormID) -> ResolvedFormID? {
        index.placedReferences[ESSPluginIndex.Key(reference)]?.space
    }

    public func script(named name: String) -> ESSExportScript? {
        index.exportScripts[name.lowercased()]
    }
}
