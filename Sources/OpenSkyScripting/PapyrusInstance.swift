// Mutable state for one attached Papyrus script instance.
//
// Variables are stored per declaring script so a parent and child may each own
// a private variable with the same name. The public initial-values seam is
// unqualified and therefore applies to the first child-to-parent match.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

/// Rises on every variable change of the instances that share it, so a cached
/// read of their variables knows when it is stale.
public final class PapyrusVariableGeneration {
    public private(set) var value = 0

    public init() {}

    public func advance() {
        value &+= 1
    }
}

public final class PapyrusInstance {
    public let handle: PapyrusObjectHandle
    public let rootScriptName: String
    public var activeState: String

    private var variablesByScript: [String: [String: PapyrusValue]]
    private let generation: PapyrusVariableGeneration?

    public init(
        handle: PapyrusObjectHandle,
        rootScriptName: String,
        activeState: String,
        variablesByScript: [String: [String: PapyrusValue]],
        generation: PapyrusVariableGeneration? = nil
    ) {
        self.handle = handle
        self.rootScriptName = rootScriptName
        self.activeState = activeState
        self.variablesByScript = variablesByScript
        self.generation = generation
    }

    public func value(named name: String, declaredBy scriptName: String) -> PapyrusValue? {
        variablesByScript[Self.key(scriptName)]?[Self.key(name)]
    }

    public func setValue(
        _ value: PapyrusValue,
        named name: String,
        declaredBy scriptName: String
    ) -> Bool {
        let scriptKey = Self.key(scriptName)
        let nameKey = Self.key(name)
        guard let old = variablesByScript[scriptKey]?[nameKey] else {
            return false
        }
        guard old != value else { return true }
        variablesByScript[scriptKey]?[nameKey] = value
        generation?.advance()
        return true
    }

    public func applyInitialValue(
        _ value: PapyrusValue,
        named name: String,
        scriptChain: [PexObject]
    ) -> Bool {
        for script in scriptChain
            where setValue(value, named: name, declaredBy: script.name)
        {
            return true
        }
        return false
    }

    /// Every Int, Float, and Bool variable as a number, by folded name. Conditions
    /// read only these types (<https://ck.uesp.net/wiki/GetVMQuestVariable>).
    public func numericVariables(into values: inout [String: Float]) {
        for variables in variablesByScript.values {
            for (name, value) in variables {
                switch value {
                case let .boolean(flag): values[name] = flag ? 1 : 0
                case let .integer(number): values[name] = Float(number)
                case let .float(number): values[name] = number
                default: continue
                }
            }
        }
    }

    /// Deterministic snapshot of every variable for save serialization,
    /// sorted by lowercased declaring-script key then variable key. Values are
    /// raw runtime values; the caller decides what is persistable.
    public func sortedVariableStates() -> [PapyrusVariableState] {
        variablesByScript
            .sorted { $0.key < $1.key }
            .flatMap { scriptKey, variables in
                variables
                    .sorted { $0.key < $1.key }
                    .map { name, value in
                        PapyrusVariableState(
                            declaringScript: scriptKey, name: name, value: value
                        )
                    }
            }
    }

    /// Restores one persisted variable. Returns false when the declaring
    /// script or the variable does not exist on this instance, so a caller
    /// can skip and count unknown save data instead of crashing.
    @discardableResult
    public func restore(_ state: PapyrusVariableState) -> Bool {
        setValue(state.value, named: state.name, declaredBy: state.declaringScript)
    }

    public static func key(_ value: String) -> String {
        PapyrusName.key(value)
    }
}

public struct PapyrusResolvedFunction {
    public let owner: PapyrusScriptIndex
    public let compiled: PapyrusCompiledFunction

    public var script: PexObject {
        owner.script
    }

    public var function: PexFunction {
        compiled.function
    }
}

nonisolated public struct PapyrusResolvedProperty: Sendable {
    public let script: PexObject
    public let property: PexProperty
}
