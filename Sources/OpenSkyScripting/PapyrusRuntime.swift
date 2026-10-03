// Long-lived Papyrus script library, instance table, and invocation façade.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

nonisolated public enum PapyrusRuntimeError: Error, Equatable {
    case missingScript(String)
    case duplicateHandle(PapyrusObjectHandle)
    case unknownInitialValue(String)
    case invalidInitialValue(name: String, expected: String, actual: String)
}

public final class PapyrusRuntime {
    public let limits: PapyrusLimits
    public let nativeDispatch: PapyrusNativeDispatch
    public let tally: PapyrusTally
    public let coercion = PapyrusCoercion()

    public var scripts: [String: PexObject] = [:]
    public var instances: [PapyrusObjectHandle: PapyrusInstance] = [:]

    private var nextHandleValue: UInt64 = 1
    private var nextSuspensionValue: UInt64 = 1

    public init(
        files: [PexFile],
        nativeDispatch: PapyrusNativeDispatch = PapyrusNativeRegistry.standard,
        limits: PapyrusLimits = .standard
    ) {
        self.limits = limits
        self.nativeDispatch = nativeDispatch
        tally = PapyrusTally(limits: limits)
        for object in files.flatMap(\.objects) {
            scripts[Self.key(object.name)] = object
        }
    }

    /// Adds a decoded file's objects to the script library, last writer wins,
    /// which is how a lazily loaded script joins a runtime built with an empty
    /// (or partial) file list.
    public func register(_ file: PexFile) {
        for object in file.objects {
            scripts[Self.key(object.name)] = object
        }
    }

    @discardableResult
    public func makeInstance(
        scriptName: String,
        handle requestedHandle: PapyrusObjectHandle? = nil,
        initialValues: [String: PapyrusValue] = [:]
    ) throws -> PapyrusObjectHandle {
        guard let root = script(named: scriptName) else {
            throw PapyrusRuntimeError.missingScript(scriptName)
        }
        let handle = requestedHandle ?? allocateHandle()
        guard instances[handle] == nil else {
            throw PapyrusRuntimeError.duplicateHandle(handle)
        }
        let chain = try scriptChain(from: root.name)
        var storage: [String: [String: PapyrusValue]] = [:]
        for script in chain {
            storage[Self.key(script.name)] = initialStorage(for: script)
        }
        let instance = PapyrusInstance(
            handle: handle,
            rootScriptName: root.name,
            // A child with no auto state starts in its parent's (CK wiki, "States (Papyrus)").
            activeState: chain.lazy.map(\.automaticStateName).first { !$0.isEmpty } ?? "",
            variablesByScript: storage
        )
        for (name, value) in initialValues {
            guard let declaration = variable(named: name, in: chain) else {
                throw PapyrusRuntimeError.unknownInitialValue(name)
            }
            guard accepts(value, as: PapyrusType(name: declaration.variable.typeName)) else {
                throw PapyrusRuntimeError.invalidInitialValue(
                    name: name,
                    expected: declaration.variable.typeName,
                    actual: value.typeName
                )
            }
            _ = instance.setValue(
                value, named: name, declaredBy: declaration.script.name
            )
        }
        instances[handle] = instance
        return handle
    }

    public func invoke(
        _ functionName: String,
        on handle: PapyrusObjectHandle,
        arguments: [PapyrusValue] = []
    ) -> PapyrusRunOutcome {
        tally.noteRun()
        return PapyrusInterpreter(runtime: self).invoke(
            functionName, on: handle, arguments: arguments
        )
    }

    public func invokeStatic(
        _ functionName: String,
        on scriptName: String,
        arguments: [PapyrusValue] = []
    ) -> PapyrusRunOutcome {
        tally.noteRun()
        return PapyrusInterpreter(runtime: self).invokeStatic(
            functionName, on: scriptName, arguments: arguments
        )
    }

    public func resume(
        _ suspendedCall: SuspendedCall,
        returning value: PapyrusValue? = nil
    ) -> PapyrusRunOutcome {
        suspendedCall.continuation.resume(
            id: suspendedCall.id,
            returning: value ?? suspendedCall.nativeCall.returnType.defaultValue
        )
    }

    public func script(named name: String) -> PexObject? {
        scripts[Self.key(name)]
    }

    public func instance(for handle: PapyrusObjectHandle) -> PapyrusInstance? {
        instances[handle]
    }

    public func scriptChain(from scriptName: String) throws(PapyrusFault) -> [PexObject] {
        var result: [PexObject] = []
        var visited: Set<String> = []
        var currentName = scriptName
        while let current = script(named: currentName) {
            let key = Self.key(current.name)
            guard visited.insert(key).inserted, result.count < limits.inheritanceDepth else {
                throw PapyrusFault.inheritanceDepthExceeded(script: current.name)
            }
            result.append(current)
            currentName = current.parentClassName
        }
        return result
    }

    public func resolvesObject(_ handle: PapyrusObjectHandle, as typeName: String) -> Bool {
        guard let instance = instance(for: handle) else {
            return false
        }
        guard let chain = try? scriptChain(from: instance.rootScriptName) else {
            return false
        }
        return chain.contains { Self.matches($0.name, typeName) }
    }

    public func accepts(_ value: PapyrusValue, as type: PapyrusType) -> Bool {
        switch (value, type) {
        case (.none, .none), (.none, .object), (.none, .array):
            true
        case (.boolean, .boolean), (.integer, .integer), (.float, .float),
             (.string, .string):
            true
        case (.object, .object):
            true
        case let (.array(array), .array(elementType)):
            array.elementType == elementType
        default:
            false
        }
    }

    public func runtimeValue(_ value: PexValue, typeName: String? = nil) -> PapyrusValue {
        switch value {
        case .null:
            typeName.map { PapyrusType(name: $0).defaultValue } ?? .none
        case .identifier:
            .none
        case let .string(value):
            .string(value)
        case let .integer(value):
            .integer(value)
        case let .float(value):
            .float(value)
        case let .boolean(value):
            .boolean(value)
        }
    }

    public func allocateSuspensionID() -> UInt64 {
        defer { nextSuspensionValue &+= 1 }
        return nextSuspensionValue
    }

    nonisolated public static func key(_ value: String) -> String {
        PapyrusName.key(value)
    }

    nonisolated public static func matches(_ left: String, _ right: String) -> Bool {
        key(left) == key(right)
    }

    private func allocateHandle() -> PapyrusObjectHandle {
        while instances[PapyrusObjectHandle(nextHandleValue)] != nil {
            nextHandleValue &+= 1
        }
        defer { nextHandleValue &+= 1 }
        return PapyrusObjectHandle(nextHandleValue)
    }

    /// First declaration wins, matching every lookup by name; see `docs/engine/papyrus-vm.md`.
    private func initialStorage(for script: PexObject) -> [String: PapyrusValue] {
        var values: [String: PapyrusValue] = [:]
        for variable in script.variables {
            let key = Self.key(variable.name)
            guard values[key] == nil else {
                tally.noteDuplicateVariable()
                continue
            }
            values[key] = runtimeValue(variable.initialValue, typeName: variable.typeName)
        }
        return values
    }

    private func variable(
        named name: String,
        in chain: [PexObject]
    ) -> (script: PexObject, variable: PexVariable)? {
        for script in chain {
            if let variable = script.variables.first(where: { Self.matches($0.name, name) }) {
                return (script, variable)
            }
        }
        return nil
    }
}
