// The AS2 runtime's queryable output (milestone 8.3.2): what it executed, what
// it could not, and what the movie traced.
//
// The milestone's stated risk-management mechanism is that an unimplemented
// opcode or an unknown host API becomes a logged no-op plus a tally entry
// rather than an error, so the tally is a first-class result and not a debug
// aid. Both name tables are capped, but every total keeps counting past the
// cap: a truncated table still reports how much it stopped naming.

import Foundation

/// Counts of everything the interpreter did not implement, plus the volume it
/// did execute.
nonisolated struct AS2Tally: Equatable {
    /// Distinct names kept per table.
    let nameLimit: Int
    /// Faults kept verbatim.
    let faultLimit: Int

    private(set) var unimplementedOpcodes: [UInt8: Int] = [:]
    /// Every unimplemented action executed, including ones past `nameLimit`.
    private(set) var unimplementedTotal = 0
    private(set) var missingNames: [String: Int] = [:]
    /// Every missing-API hit, including ones past `nameLimit`.
    private(set) var missingTotal = 0
    /// Missing-API hits that arrived after `missingNames` was full.
    private(set) var unnamedMissing = 0
    private(set) var faults: [AS2Fault] = []
    /// Every fault raised, including ones past `faultLimit`.
    private(set) var faultTotal = 0

    /// Empty-stack reads. Flash tolerates these and vanilla bytecode relies on
    /// it, so they are counted rather than raised.
    private(set) var stackUnderflows = 0
    private(set) var actionsExecuted = 0
    private(set) var blocksExecuted = 0
    private(set) var callsPerformed = 0

    init(limits: AS2Limits = .standard) {
        nameLimit = limits.tallyNames
        faultLimit = limits.faultRecords
    }

    /// An opcode the dispatch table has no implementation for. Vanilla movies
    /// use 56 opcodes and all 56 are implemented, so anything counted here came
    /// from a mod, a newer movie, or malformed bytes.
    mutating func noteUnimplemented(opcode: UInt8) {
        unimplementedTotal += 1
        if unimplementedOpcodes[opcode] != nil || unimplementedOpcodes.count < nameLimit {
            unimplementedOpcodes[opcode, default: 0] += 1
        }
    }

    /// A member, variable, or class the runtime cannot resolve — the `MovieClip`
    /// and `gfx` surface a later milestone fills in.
    mutating func noteMissing(_ name: String) {
        missingTotal += 1
        if missingNames[name] != nil || missingNames.count < nameLimit {
            missingNames[name, default: 0] += 1
        } else {
            unnamedMissing += 1
        }
    }

    mutating func noteStackUnderflow() {
        stackUnderflows += 1
    }

    mutating func note(fault: AS2Fault) {
        faultTotal += 1
        if faults.count < faultLimit {
            faults.append(fault)
        }
    }

    mutating func noteBlock(actions: Int) {
        blocksExecuted += 1
        actionsExecuted += actions
    }

    mutating func noteCall() {
        callsPerformed += 1
    }

    var isClean: Bool {
        unimplementedTotal == 0 && missingTotal == 0 && faultTotal == 0
    }

    /// Opcodes ranked by count, ties broken by opcode so the order is stable.
    var rankedUnimplemented: [(name: String, count: Int)] {
        unimplementedOpcodes
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { (AS2Tally.opcodeName($0.key), $0.value) }
    }

    /// Missing API names ranked by count, ties broken alphabetically.
    var rankedMissing: [(name: String, count: Int)] {
        missingNames
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    static func opcodeName(_ code: UInt8) -> String {
        SWFActionName.name(forCode: code) ?? String(format: "0x%02X", code)
    }
}

/// `ActionTrace` (0x26) output. Bounded in both directions: at most
/// `entryLimit` messages are kept (oldest dropped) and each is clipped to
/// `messageLimit` characters, so a looping trace cannot grow without bound.
nonisolated struct AS2TraceLog: Equatable {
    let entryLimit: Int
    let messageLimit: Int

    private(set) var messages: [String] = []
    /// Every message traced, including ones already dropped.
    private(set) var total = 0

    init(limits: AS2Limits = .standard) {
        entryLimit = limits.traceEntries
        messageLimit = limits.traceLength
    }

    /// Messages dropped to stay inside `entryLimit`.
    var dropped: Int {
        max(0, total - messages.count)
    }

    mutating func append(_ message: String) {
        total += 1
        let clipped = message.count > messageLimit
            ? String(message.prefix(messageLimit))
            : message
        messages.append(clipped)
        if messages.count > entryLimit {
            messages.removeFirst(messages.count - entryLimit)
        }
    }

    mutating func clear() {
        messages.removeAll()
        total = 0
    }
}
