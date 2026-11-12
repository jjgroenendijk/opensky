// Papyrus state into OpenSky script state: each instance's variables by script and
// variable name. Values with runtime identity (objects, arrays) and stacks cannot
// cross VMs, so they are counted and dropped.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyScriptingInterface

nonisolated extension ESSPapyrusImport {
    func importPapyrus() {
        let papyrus: ESSPapyrus
        do {
            guard let decoded = try importer.file.papyrus() else {
                importer.report.update("scripts") { $0.skip("no Papyrus table") }
                return
            }
            papyrus = decoded
        } catch {
            importer.report.update("scripts") { $0.skip("Papyrus table: \(error)") }
            return
        }
        for instance in papyrus.instances {
            importInstance(instance, papyrus: papyrus)
        }
        importer.report.update("scripts") { category in
            category.drop("alias and other reference objects", count: papyrus.references.count)
            if let blocked = papyrus.stackStatus.blockedBy {
                category.skip(blocked)
            }
        }
        for active in papyrus.activeScripts {
            importer.report.droppedStacks[
                papyrus.activeScriptNames[active.id] ?? "unnamed",
                default: 0
            ] += 1
        }
        for stack in papyrus.suspendedStacks {
            importer.report.droppedStacks[stack.scriptName ?? "unnamed suspended", default: 0] += 1
        }
    }

    private func importInstance(_ instance: ESSPapyrusInstance, papyrus: ESSPapyrus) {
        guard case let .success(key) = importer.key(for: instance.form) else {
            importer.report.update("scripts") { $0.drop("instance on an unmapped form") }
            return
        }
        guard let declared = importer.records.declaredVariables(ofScript: instance.scriptName)
        else {
            importer.report.update("scripts") { $0.drop("script \(instance.scriptName) not found") }
            return
        }
        guard let names = memberNames(of: instance, papyrus: papyrus) else {
            importer.report
                .update("scripts") { $0.drop("variable count differs from the definition") }
            return
        }
        var variables: [PapyrusVariableState] = []
        for (name, value) in zip(names, instance.variables) {
            guard let owner = declared[name.lowercased()] else {
                importer.report.update("scripts") { $0.drop("undeclared variable") }
                continue
            }
            guard let converted = Self.value(value) else {
                importer.report
                    .update("scripts") {
                        $0.drop("\(value.kindName) value (handles do not cross VMs)")
                    }
                continue
            }
            variables.append(PapyrusVariableState(
                declaringScript: owner,
                name: name,
                value: converted
            ))
        }
        importer.scripts.append(PapyrusInstanceState(
            key: PapyrusInstanceKey(reference: key, scriptName: instance.scriptName),
            activeState: "",
            variables: variables.sorted(by: Self.variableOrder),
            hasFiredOnInit: true
        ))
        importer.report.update("scripts") { category in
            category.imported += variables.count
            category.skip("script state name (undocumented)")
        }
    }

    private static func variableOrder(
        _ left: PapyrusVariableState, _ right: PapyrusVariableState
    ) -> Bool {
        (left.declaringScript, left.name) < (right.declaringScript, right.name)
    }

    /// The save lists a script's own members; an instance whose count matches the
    /// whole parent chain lists the parents' first.
    private func memberNames(of instance: ESSPapyrusInstance, papyrus: ESSPapyrus) -> [String]? {
        var chain: [ESSPapyrusScript] = []
        var name = instance.scriptName
        while let script = papyrus.script(named: name), chain.count < 32 {
            chain.insert(script, at: 0)
            name = script.parent
        }
        let own = chain.last?.members.map(\.name) ?? []
        if own.count == instance.variables.count {
            return own
        }
        let all = chain.flatMap { $0.members.map(\.name) }
        return all.count == instance.variables.count ? all : nil
    }

    static func value(_ value: ESSPapyrusValue) -> PapyrusValue? {
        switch value {
        case .null: PapyrusValue.none
        case let .string(text): .string(text)
        case let .integer(number): .integer(number)
        case let .float(number): .float(number)
        case let .boolean(flag): .boolean(flag)
        case .object, .array: nil
        }
    }

    func importCreatedObjects() {
        guard let objects = attempt({ try importer.file.createdObjects() }) else {
            importer.report.update("created forms") { $0.skip("created objects table") }
            return
        }
        for object in objects {
            importer.report.update("created forms") { $0.drop("created \(object.kind.rawValue)") }
        }
    }
}
