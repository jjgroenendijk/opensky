// One script's functions and property handlers, compiled once, and its member lookups
// by spelling. `PapyrusRuntime.index(named:)` builds it on first use and drops it when
// the script library changes.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

public final class PapyrusScriptIndex {
    public typealias DeclaredVariable = (owner: PexObject, variable: PexVariable)

    public let script: PexObject

    /// Folded state name, then folded function name. The first state and the first
    /// function of a name win, as in a lookup by name.
    private let functionsByState: [String: [String: PapyrusCompiledFunction]]
    private let readHandlers: [String: PapyrusCompiledFunction]
    private let writeHandlers: [String: PapyrusCompiledFunction]
    private var functionsBySpelling: [String: [String: PapyrusCompiledFunction?]] = [:]
    private var variablesBySpelling: [String: DeclaredVariable?] = [:]
    private var variablesGeneration: Int?

    public init(_ script: PexObject) {
        self.script = script
        var states: [String: [String: PapyrusCompiledFunction]] = [:]
        for state in script.states where states[PapyrusName.key(state.name)] == nil {
            var functions: [String: PapyrusCompiledFunction] = [:]
            for named in state.functions where functions[PapyrusName.key(named.name)] == nil {
                functions[PapyrusName.key(named.name)] = PapyrusCompiledFunction(named.function)
            }
            states[PapyrusName.key(state.name)] = functions
        }
        functionsByState = states
        var reads: [String: PapyrusCompiledFunction] = [:]
        var writes: [String: PapyrusCompiledFunction] = [:]
        var seen: Set<String> = []
        for property in script.properties {
            let key = PapyrusName.key(property.name)
            guard seen.insert(key).inserted else { continue }
            reads[key] = property.readHandler.map(PapyrusCompiledFunction.init)
            writes[key] = property.writeHandler.map(PapyrusCompiledFunction.init)
        }
        readHandlers = reads
        writeHandlers = writes
    }

    public func function(named name: String, state: String) -> PapyrusCompiledFunction? {
        if let known = functionsBySpelling[state]?[name] {
            return known
        }
        let found = functionsByState[PapyrusName.key(state)]?[PapyrusName.key(name)]
        functionsBySpelling[state, default: [:]][name] = .some(found)
        return found
    }

    /// The handler of the first property named `name`, as `PexProperty` holds it.
    public func handler(ofProperty name: String, writing: Bool) -> PapyrusCompiledFunction? {
        (writing ? writeHandlers : readHandlers)[PapyrusName.key(name)]
    }

    /// The first variable named `name` in this script, then in each parent. `generation`
    /// is the library's, because a parent loaded later can change the answer.
    public func declaredVariable(
        _ name: String,
        generation: Int,
        parents: () throws(PapyrusFault) -> [PexObject]
    ) throws(PapyrusFault) -> DeclaredVariable? {
        if variablesGeneration != generation {
            variablesBySpelling.removeAll(keepingCapacity: true)
            variablesGeneration = generation
        }
        if let known = variablesBySpelling[name] {
            return known
        }
        var found: DeclaredVariable?
        for owner in try [script] + parents() {
            if let variable = owner.variables.first(where: { PapyrusName.matches($0.name, name) }) {
                found = (owner, variable)
                break
            }
        }
        variablesBySpelling[name] = .some(found)
        return found
    }
}
