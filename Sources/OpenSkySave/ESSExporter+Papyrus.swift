// Script state into the Papyrus table: one instance per script on a form, with every
// variable of its script chain. A script with object or array variables is left out,
// because a none handle there would replace what the plugin's properties set.

import Foundation
import OpenSkyFormatsESS
import OpenSkyScriptingInterface

nonisolated extension ESSExporter {
    mutating func exportScripts() {
        var defined: Set<String> = []
        for state in contents.scripts {
            guard let chain = scriptChain(state.key.scriptName) else {
                report.update("scripts") { $0.drop("script \(state.key.scriptName) not found") }
                continue
            }
            guard let instance = instance(state, chain: chain) else { continue }
            for script in chain where defined.insert(script.name.lowercased()).inserted {
                let members = script.variables.map {
                    ESSPapyrusMember(name: $0.name, type: $0.typeName)
                }
                papyrus.scripts.append(
                    ESSPapyrusScript(name: script.name, parent: script.parent, members: members)
                )
            }
            papyrus.instances.append(instance)
        }
        let timers = contents.timers.count
        report.update("scripts") { $0.drop("pending update timers", count: timers) }
    }

    /// The script and its parents, the root first, or nil when one is missing.
    private func scriptChain(_ name: String) -> [ESSExportScript]? {
        var chain: [ESSExportScript] = []
        var next = name
        while !next.isEmpty, chain.count < 32 {
            guard let script = records.script(named: next) else { return nil }
            chain.insert(script, at: 0)
            next = script.parent
        }
        return chain
    }

    private mutating func instance(
        _ state: PapyrusInstanceState, chain: [ESSExportScript]
    ) -> ESSPapyrusInstance? {
        let variables = chain.flatMap { script in script.variables.map { (script.name, $0) } }
        if variables.contains(where: \.1.holdsHandle) {
            report.update("scripts") { $0.drop("script with object or array variables") }
            return nil
        }
        guard state.hasFiredOnInit else {
            report.update("scripts") { $0.drop("script whose OnInit has not run") }
            return nil
        }
        guard let form = forms.ref(state.key.reference) else {
            report.update("scripts") { $0.drop("script on a form the save cannot name") }
            return nil
        }
        var saved: [String: PapyrusValue] = [:]
        for variable in state.variables {
            saved[Self.variableKey(variable.declaringScript, variable.name)] = variable.value
        }
        let values = variables.map { owner, variable in
            Self.value(saved[Self.variableKey(owner, variable.name)] ?? variable.initial)
        }
        report.update("scripts") { category in
            category.written += state.variables.count
            if !state.activeState.isEmpty {
                category.drop("script state name (not written)")
            }
        }
        return ESSPapyrusInstance(
            id: UInt64(papyrus.instances.count + 1),
            scriptName: chain.last?.name ?? state.key.scriptName, form: form, variables: values
        )
    }

    private static func variableKey(_ script: String, _ name: String) -> String {
        script.lowercased() + "." + name.lowercased()
    }

    /// Only scalar values reach here; the instance check leaves out handles.
    static func value(_ value: PapyrusValue) -> ESSPapyrusValue {
        switch value {
        case .none, .object, .array: .null
        case let .boolean(flag): .boolean(flag)
        case let .integer(number): .integer(number)
        case let .float(number): .float(number)
        case let .string(text): .string(text)
        }
    }
}
