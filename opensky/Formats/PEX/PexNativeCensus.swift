// Native declarations and typed call sites resolved across a PEX corpus.

import Foundation

nonisolated struct PexNativeTarget: Equatable, Hashable, Sendable {
    let scriptName: String
    let functionName: String

    var name: String {
        "\(scriptName).\(functionName)"
    }

    var key: PapyrusNativeKey {
        PapyrusNativeKey(scriptName: scriptName, functionName: functionName)
    }
}

nonisolated struct PexNativeCoverage: Equatable, Sendable {
    let implemented: Int
    let referenced: Int

    var percentage: Double {
        guard referenced > 0 else { return 100 }
        return Double(implemented) / Double(referenced) * 100
    }
}

nonisolated struct PexNativeCensus: Equatable, Sendable {
    private(set) var declarationTotal = 0
    private(set) var declarations: [PapyrusNativeKey: PexNativeTarget] = [:]
    private(set) var referenceCounts: [PexNativeTarget: Int] = [:]

    init(files: [PexFile]) {
        let objects = files.flatMap(\.objects)
        let scripts = Dictionary(
            objects.map { (PapyrusRuntime.key($0.name), $0) },
            uniquingKeysWith: { _, last in last }
        )
        recordDeclarations(objects)
        for object in objects {
            recordReferences(in: object, scripts: scripts)
        }
    }

    var distinctReferencedTotal: Int {
        referenceCounts.count
    }

    var referenceTotal: Int {
        referenceCounts.values.reduce(0, +)
    }

    var rankedReferences: [(name: String, count: Int)] {
        referenceCounts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    func coverage(in registry: PapyrusNativeRegistry) -> PexNativeCoverage {
        let implemented = referenceCounts.keys.reduce(into: 0) { count, target in
            if
                registry.contains(
                    scriptName: target.scriptName,
                    functionName: target.functionName
                )
            {
                count += 1
            }
        }
        return PexNativeCoverage(
            implemented: implemented,
            referenced: distinctReferencedTotal
        )
    }

    private mutating func recordDeclarations(_ objects: [PexObject]) {
        for object in objects {
            for state in object.states {
                for named in state.functions where named.function.flags.contains(.native) {
                    declarationTotal += 1
                    let target = PexNativeTarget(
                        scriptName: object.name,
                        functionName: named.name
                    )
                    declarations[target.key] = target
                }
            }
        }
    }

    private mutating func recordReferences(
        in object: PexObject,
        scripts: [String: PexObject]
    ) {
        for state in object.states {
            for named in state.functions {
                for instruction in named.function.instructions {
                    guard
                        let target = nativeTarget(
                            instruction,
                            function: named.function,
                            object: object,
                            scripts: scripts
                        )
                    else { continue }
                    referenceCounts[target, default: 0] += 1
                }
            }
        }
    }

    private func nativeTarget(
        _ instruction: PexInstruction,
        function: PexFunction,
        object: PexObject,
        scripts: [String: PexObject]
    ) -> PexNativeTarget? {
        let operands = instruction.operands
        switch instruction.opcode {
        case .callStatic:
            guard
                operands.count >= 2,
                let scriptName = operands[0].stringValue,
                let functionName = operands[1].stringValue
            else { return nil }
            return resolve(
                functionName,
                startingAt: scriptName,
                scripts: scripts
            )
        case .callParent:
            guard let functionName = operands.first?.stringValue else { return nil }
            return resolve(
                functionName,
                startingAt: object.parentClassName,
                scripts: scripts
            )
        case .callMethod:
            guard
                operands.count >= 2,
                let functionName = operands[0].stringValue,
                let receiverType = receiverType(
                    operands[1],
                    function: function,
                    object: object
                )
            else { return nil }
            return resolve(
                functionName,
                startingAt: receiverType,
                scripts: scripts
            )
        default:
            return nil
        }
    }

    private func receiverType(
        _ operand: PexValue,
        function: PexFunction,
        object: PexObject
    ) -> String? {
        guard case let .identifier(name) = operand else { return nil }
        if
            PapyrusRuntime.matches(name, "self")
            || PapyrusRuntime.matches(name, "_self")
        {
            return object.name
        }
        if
            let typed = (function.parameters + function.localVariables)
                .first(where: { PapyrusRuntime.matches($0.name, name) })
        {
            return objectType(typed.typeName)
        }
        if
            let variable = object.variables.first(where: {
                PapyrusRuntime.matches($0.name, name)
            })
        {
            return objectType(variable.typeName)
        }
        if
            let property = object.properties.first(where: {
                PapyrusRuntime.matches($0.automaticVariableName ?? "", name)
                    || PapyrusRuntime.matches($0.name, name)
            })
        {
            return objectType(property.typeName)
        }
        return nil
    }

    private func objectType(_ name: String) -> String? {
        switch PapyrusType(name: name) {
        case let .object(objectName):
            objectName
        default:
            nil
        }
    }

    private func resolve(
        _ functionName: String,
        startingAt scriptName: String,
        scripts: [String: PexObject]
    ) -> PexNativeTarget? {
        var currentName = scriptName
        var visited: Set<String> = []
        while !currentName.isEmpty {
            let key = PapyrusRuntime.key(currentName)
            guard visited.insert(key).inserted else { return nil }
            if
                let target = declarations[
                    PapyrusNativeKey(
                        scriptName: currentName,
                        functionName: functionName
                    )
                ]
            {
                return target
            }
            guard let script = scripts[key] else { return nil }
            currentName = script.parentClassName
        }
        return nil
    }
}
