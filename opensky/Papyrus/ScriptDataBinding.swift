// Bridges decoded VMAD property values to the initial-values seam on
// `PapyrusRuntime.makeInstance`. World identity stays a `ReferenceKey` until
// the caller supplies the opaque Papyrus handle for that live reference.

import Foundation
import OSLog

nonisolated enum ScriptBindingError: Error, Equatable {
    case removedScript(String)
}

nonisolated enum ScriptBindingSkipReason: Hashable {
    case removedProperty
    case missingProperty
    case manualProperty
    case missingBackingVariable
    case aliasObject
    case unresolvedReference
    case typeMismatch

    var name: String {
        switch self {
        case .removedProperty: "removed property"
        case .missingProperty: "property missing from PEX"
        case .manualProperty: "non-automatic property"
        case .missingBackingVariable: "automatic property without backing variable"
        case .aliasObject: "quest-alias object"
        case .unresolvedReference: "unresolved object reference"
        case .typeMismatch: "VMAD/PEX type mismatch"
        }
    }
}

nonisolated struct ScriptBindingTally: Equatable {
    private(set) var counts: [ScriptBindingSkipReason: Int] = [:]

    var total: Int {
        counts.values.reduce(0, +)
    }

    var ranked: [(name: String, count: Int)] {
        counts
            .sorted {
                $0.value == $1.value
                    ? $0.key.name < $1.key.name
                    : $0.value > $1.value
            }
            .map { ($0.key.name, $0.value) }
    }

    mutating func note(_ reason: ScriptBindingSkipReason) {
        counts[reason, default: 0] += 1
    }

    mutating func merge(_ other: ScriptBindingTally) {
        for (reason, count) in other.counts {
            counts[reason, default: 0] += count
        }
    }
}

nonisolated struct ScriptBinding {
    let initialValues: [String: PapyrusValue]
    /// Direct VMAD FormIDs that resolved all the way through
    /// `FormIDResolver` -> `ReferenceKey` -> caller-owned opaque handle.
    let resolvedReferences: [ReferenceKey]
    let skipped: ScriptBindingTally
}

nonisolated struct BoundScriptInstance {
    let handle: PapyrusObjectHandle
    let binding: ScriptBinding
}

nonisolated extension AttachedScript {
    /// Creates one instance through the issue #168 initial-values seam.
    ///
    /// Alias objects and direct references with no live opaque handle leave
    /// the PEX compiler default intact. The caller owns world-reference handle
    /// allocation; M11.2 supplies that lifecycle.
    func makeInstance(
        in runtime: PapyrusRuntime,
        handle: PapyrusObjectHandle? = nil,
        formIDResolver: FormIDResolver,
        objectHandle: @escaping (ReferenceKey) -> PapyrusObjectHandle?
    ) throws -> BoundScriptInstance {
        let binding = try binding(
            in: runtime,
            formIDResolver: formIDResolver,
            objectHandle: objectHandle
        )
        let instanceHandle = try runtime.makeInstance(
            scriptName: name,
            handle: handle,
            initialValues: binding.initialValues
        )
        return BoundScriptInstance(handle: instanceHandle, binding: binding)
    }

    func binding(
        in runtime: PapyrusRuntime,
        formIDResolver: FormIDResolver,
        objectHandle: @escaping (ReferenceKey) -> PapyrusObjectHandle?
    ) throws -> ScriptBinding {
        guard !isRemoved else {
            throw ScriptBindingError.removedScript(name)
        }
        guard let root = runtime.script(named: name) else {
            throw PapyrusRuntimeError.missingScript(name)
        }
        let chain = try runtime.scriptChain(from: root.name)
        var builder = ScriptBindingBuilder(
            scriptName: name,
            formIDResolver: formIDResolver,
            objectHandle: objectHandle
        )
        for property in properties {
            builder.bind(property, chain: chain, runtime: runtime)
        }
        return builder.result
    }
}

nonisolated private struct ScriptBindingBuilder {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "ScriptDataBinding"
    )

    let scriptName: String
    let formIDResolver: FormIDResolver
    let objectHandle: (ReferenceKey) -> PapyrusObjectHandle?
    var initialValues: [String: PapyrusValue] = [:]
    var resolvedReferences: [ReferenceKey] = []
    var skipped = ScriptBindingTally()

    var result: ScriptBinding {
        ScriptBinding(
            initialValues: initialValues,
            resolvedReferences: resolvedReferences,
            skipped: skipped
        )
    }

    mutating func bind(
        _ property: ScriptProperty,
        chain: [PexObject],
        runtime: PapyrusRuntime
    ) {
        guard !property.flags.contains(.removed) else {
            skip(.removedProperty, property: property.name)
            return
        }
        guard let resolved = resolvedProperty(named: property.name, chain: chain) else {
            skip(.missingProperty, property: property.name)
            return
        }
        guard resolved.property.flags.contains(.automatic) else {
            skip(.manualProperty, property: property.name)
            return
        }
        guard let backingName = resolved.property.automaticVariableName else {
            skip(.missingBackingVariable, property: property.name)
            return
        }
        let expectedType = PapyrusType(name: resolved.property.typeName)
        guard
            let converted = convert(
                property.value,
                expectedType: expectedType,
                propertyName: property.name
            )
        else {
            return
        }
        guard runtime.accepts(converted.value, as: expectedType) else {
            skip(.typeMismatch, property: property.name)
            return
        }
        initialValues[backingName] = converted.value
        resolvedReferences.append(contentsOf: converted.references)
    }

    private func resolvedProperty(
        named name: String,
        chain: [PexObject]
    ) -> PapyrusResolvedProperty? {
        for script in chain {
            if
                let property = script.properties.first(where: {
                    PapyrusRuntime.matches($0.name, name)
                })
            {
                return PapyrusResolvedProperty(script: script, property: property)
            }
        }
        return nil
    }

    private mutating func convert(
        _ value: ScriptPropertyValue,
        expectedType: PapyrusType,
        propertyName: String
    ) -> ResolvedScriptValue? {
        switch value {
        case .none:
            ResolvedScriptValue(value: .none)
        case let .object(object):
            resolve(object, propertyName: propertyName)
        case let .string(value):
            ResolvedScriptValue(value: .string(value))
        case let .integer(value):
            ResolvedScriptValue(value: .integer(value))
        case let .float(value):
            ResolvedScriptValue(value: .float(value))
        case let .boolean(value):
            ResolvedScriptValue(value: .boolean(value))
        case let .objects(values):
            resolve(
                values,
                expectedType: expectedType,
                propertyName: propertyName
            )
        case let .strings(values):
            ResolvedScriptValue(value: .array(PapyrusArray(
                elementType: .string,
                elements: values.map(PapyrusValue.string)
            )))
        case let .integers(values):
            ResolvedScriptValue(value: .array(PapyrusArray(
                elementType: .integer,
                elements: values.map(PapyrusValue.integer)
            )))
        case let .floats(values):
            ResolvedScriptValue(value: .array(PapyrusArray(
                elementType: .float,
                elements: values.map(PapyrusValue.float)
            )))
        case let .booleans(values):
            ResolvedScriptValue(value: .array(PapyrusArray(
                elementType: .boolean,
                elements: values.map(PapyrusValue.boolean)
            )))
        }
    }

    private mutating func resolve(
        _ values: [ScriptObjectReference],
        expectedType: PapyrusType,
        propertyName: String
    ) -> ResolvedScriptValue? {
        let elementType: PapyrusType = if case let .array(expectedElement) = expectedType {
            expectedElement
        } else {
            .object("Object")
        }
        var elements: [PapyrusValue] = []
        var references: [ReferenceKey] = []
        elements.reserveCapacity(values.count)
        for value in values {
            guard let resolved = resolve(value, propertyName: propertyName) else {
                return nil
            }
            elements.append(resolved.value)
            references.append(contentsOf: resolved.references)
        }
        return ResolvedScriptValue(
            value: .array(PapyrusArray(elementType: elementType, elements: elements)),
            references: references
        )
    }

    private mutating func resolve(
        _ value: ScriptObjectReference,
        propertyName: String
    ) -> ResolvedScriptValue? {
        guard !value.isAlias else {
            skip(.aliasObject, property: propertyName)
            return nil
        }
        guard !value.formID.isNull else {
            return ResolvedScriptValue(value: .none)
        }
        guard let key = value.directReferenceKey(using: formIDResolver) else {
            skip(.unresolvedReference, property: propertyName)
            return nil
        }
        guard let handle = objectHandle(key) else {
            skip(.unresolvedReference, property: propertyName)
            return nil
        }
        return ResolvedScriptValue(value: .object(handle), references: [key])
    }

    private mutating func skip(_ reason: ScriptBindingSkipReason, property: String) {
        skipped.note(reason)
        let boundScriptName = scriptName
        let reasonName = reason.name
        let attachment = "\(boundScriptName).\(property)"
        Self.logger.warning(
            "VMAD \(attachment, privacy: .public) default retained: \(reasonName, privacy: .public)"
        )
    }
}

nonisolated private struct ResolvedScriptValue {
    let value: PapyrusValue
    let references: [ReferenceKey]

    init(value: PapyrusValue, references: [ReferenceKey] = []) {
        self.value = value
        self.references = references
    }
}
