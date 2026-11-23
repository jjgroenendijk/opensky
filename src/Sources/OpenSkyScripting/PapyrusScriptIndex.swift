// One script's functions and property handlers, compiled once, and its member lookups
// by spelling. `PapyrusRuntime.index(named:)` builds it on first use and drops it when
// the script library changes.

import Foundation
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

final class PapyrusScriptIndex {
    typealias DeclaredVariable = (owner: PexObject, variable: PexVariable)

    let script: PexObject
    /// The folded script name, the script half of a native key.
    let key: String

    /// Folded state name, then folded function name. The first state and the first
    /// function of a name win, as in a lookup by name.
    private let functionsByState: [String: [String: PapyrusCompiledFunction]]
    private let readHandlers: [String: PapyrusCompiledFunction]
    private let writeHandlers: [String: PapyrusCompiledFunction]
    /// Every function and property handler, at its `ordinal`.
    private let functionsByOrdinal: [PapyrusCompiledFunction]
    private var functionsBySpelling: [String: [String: PapyrusCompiledFunction?]] = [:]
    /// Folded names of the functions declared native in any state.
    private let nativeFunctions: Set<String>
    private var nativeBySpelling: [String: Bool] = [:]
    private var variablesBySpelling: [String: DeclaredVariable?] = [:]
    private var variablesGeneration: Int?
    var callSites = PapyrusCallSites()

    init(_ script: PexObject) {
        self.script = script
        key = PapyrusName.key(script.name)
        nativeFunctions = Set(script.states.flatMap { state in
            state.functions.filter { $0.function.flags.contains(.native) }
                .map { PapyrusName.key($0.name) }
        })
        var states: [String: [String: PapyrusCompiledFunction]] = [:]
        var ordinal = 0
        for state in script.states where states[PapyrusName.key(state.name)] == nil {
            var functions: [String: PapyrusCompiledFunction] = [:]
            for named in state.functions where functions[PapyrusName.key(named.name)] == nil {
                functions[PapyrusName.key(named.name)] = PapyrusCompiledFunction(
                    named.function, ordinal: ordinal
                )
                ordinal += 1
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
            if let handler = property.readHandler {
                reads[key] = PapyrusCompiledFunction(handler, ordinal: ordinal)
                ordinal += 1
            }
            if let handler = property.writeHandler {
                writes[key] = PapyrusCompiledFunction(handler, ordinal: ordinal)
                ordinal += 1
            }
        }
        readHandlers = reads
        writeHandlers = writes
        let all = states.values.flatMap(\.values) + reads.values + writes.values
        functionsByOrdinal = all.sorted { $0.ordinal < $1.ordinal }
    }

    /// The function a saved frame names, or nil when the script has fewer functions now.
    func function(ordinal: Int) -> PapyrusCompiledFunction? {
        functionsByOrdinal.indices.contains(ordinal) ? functionsByOrdinal[ordinal] : nil
    }

    func function(named name: String, state: String) -> PapyrusCompiledFunction? {
        if let known = functionsBySpelling[state]?[name] {
            return known
        }
        let found = functionsByState[PapyrusName.key(state)]?[PapyrusName.key(name)]
        functionsBySpelling[state, default: [:]][name] = .some(found)
        return found
    }

    /// Whether any state declares a native function spelled `name`.
    func declaresNative(_ name: String) -> Bool {
        if let known = nativeBySpelling[name] {
            return known
        }
        let found = nativeFunctions.contains(PapyrusName.key(name))
        nativeBySpelling[name] = found
        return found
    }

    /// The handler of the first property named `name`, as `PexProperty` holds it.
    func handler(ofProperty name: String, writing: Bool) -> PapyrusCompiledFunction? {
        (writing ? writeHandlers : readHandlers)[PapyrusName.key(name)]
    }

    /// The first variable named `name` in this script, then in each parent. `generation`
    /// is the library's, because a parent loaded later can change the answer.
    func declaredVariable(
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
