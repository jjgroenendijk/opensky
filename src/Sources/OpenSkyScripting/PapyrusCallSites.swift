// What each call instruction of a script resolved to, so a later run of the same call
// skips the name lookups. A script's functions do not change after load, so the answer
// holds while the library, the receiver's script, and its state stay the same.

import Foundation
import OpenSkyFormatsPEX

/// Where a call goes: a function written in Papyrus, or native dispatch.
enum PapyrusCallTarget {
    case function(PapyrusResolvedFunction)
    /// `key` is the folded script name, nil when no loaded script has it.
    case native(script: String, key: String?)
}

/// One call site's last answer and the inputs it was found for.
struct PapyrusCallSite {
    let generation: Int
    /// The receiver's root script; empty for a receiver with no script instance.
    let script: String
    let state: String
    let target: PapyrusCallTarget

    func holds(generation: Int, script: String, state: String) -> Bool {
        self.generation == generation && self.script == script && self.state == state
    }
}

/// The call sites of every function of one script, by function ordinal and instruction.
struct PapyrusCallSites {
    private var sites: [[PapyrusCallSite?]] = []

    func site(of compiled: PapyrusCompiledFunction, at instruction: Int) -> PapyrusCallSite? {
        guard sites.indices.contains(compiled.ordinal) else { return nil }
        let row = sites[compiled.ordinal]
        return row.indices.contains(instruction) ? row[instruction] : nil
    }

    mutating func keep(
        _ site: PapyrusCallSite, of compiled: PapyrusCompiledFunction, at instruction: Int
    ) {
        let count = compiled.function.instructions.count
        guard compiled.ordinal >= 0, instruction >= 0, instruction < count else { return }
        if sites.count <= compiled.ordinal {
            sites += Array(repeating: [], count: compiled.ordinal + 1 - sites.count)
        }
        if sites[compiled.ordinal].isEmpty {
            sites[compiled.ordinal] = Array(repeating: nil, count: count)
        }
        sites[compiled.ordinal][instruction] = site
    }
}
