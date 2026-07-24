// AS2 opcode/API inventory (milestone 8.3.1 stage 2): tallies what
// ActionScript bytecode the movies handed to `record(_:path:)` actually use —
// opcode frequency, the host/GFx member and method names reached through
// ActionGetMember/ActionSetMember/ActionCallMethod/ActionCallFunction/
// ActionGetVariable/ActionSetVariable/ActionNewMethod/ActionDefineLocal,
// clip-event handler usage, and function/structure statistics. This is the
// evidence for the 8.3.1 decision doc (`docs/decisions/swf-as2-scope.md`); it
// executes nothing, and never throws.
//
// Host/API name resolution is a structural heuristic, not stack simulation:
// the record immediately before one of the tracked opcodes is checked for an
// `ActionPush` whose last (topmost) pushed value is a literal string or a
// constant-pool reference, resolved against the most recent
// `ActionConstantPool` seen earlier in the same block. Compiler-emitted GFx
// member/method lookups push the name directly before the opcode that
// consumes it, so this recovers the great majority of names without modeling
// the AS2 operand stack.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 5
// "Actions" — ActionGetMember/ActionSetMember (p. 87), ActionCallMethod/
// ActionNewMethod (p. 88), ActionCallFunction (p. 82), ActionGetVariable/
// ActionSetVariable (pp. 76-77), ActionDefineLocal (p. 89).

import Foundation

/// One movie's action-side summary line.
nonisolated struct SWFActionMovieSummary: Equatable {
    let path: String
    let actionBlocks: Int
    let actionRecords: Int
    let distinctOpcodes: Int
    let unknownOpcodes: Int
    let undecodedOpcodes: Int
    let warnings: Int
}

/// Accumulates the action-side inventory across every movie `record(_:path:)`
/// is called with. A pure value type: no I/O, no printing — `openskycli`
/// formats and prints what this collects.
struct SWFActionInventory {
    private(set) var movies: [SWFActionMovieSummary] = []
    private(set) var opcodeCounts: [UInt8: Int] = [:]
    private(set) var opcodeMovies: [UInt8: Set<String>] = [:]
    private(set) var unknownOpcodeMovies: [UInt8: Set<String>] = [:]
    private(set) var hostNameCounts: [String: Int] = [:]
    private(set) var hostNameMovies: [String: Set<String>] = [:]
    private(set) var clipEventCounts: [String: Int] = [:]
    private(set) var clipEventMovies: [String: Set<String>] = [:]

    private(set) var defineFunctionCount = 0
    private(set) var defineFunction2Count = 0
    private(set) var maxRegisterCount: UInt8 = 0
    private(set) var withCount = 0
    private(set) var tryCount = 0
    private(set) var constantPoolCount = 0
    private(set) var maxConstantPoolSize = 0
    private(set) var maxBlockBytes = 0
    private(set) var maxBlockRecords = 0
    private(set) var doActionBlockCount = 0
    private(set) var doInitActionBlockCount = 0
    private(set) var clipActionBlockCount = 0

    var distinctOpcodeCount: Int {
        opcodeCounts.keys.count
    }

    var distinctHostNameCount: Int {
        hostNameCounts.keys.count
    }

    /// Member/function-name opcodes whose immediately preceding pushed value
    /// names the host API surface being reached.
    private static let hostAPICodes: Set<UInt8> = [0x1C, 0x1D, 0x3C, 0x3D, 0x4E, 0x4F, 0x52, 0x53]

    /// `SWFClipEventFlags` case name paired with its flag, in bit order — a
    /// fixed, deterministic report order rather than one sorted by count.
    private static let clipEventTable: [(name: String, flag: SWFClipEventFlags)] = [
        ("load", .load), ("enterFrame", .enterFrame), ("unload", .unload),
        ("mouseMove", .mouseMove), ("mouseDown", .mouseDown), ("mouseUp", .mouseUp),
        ("keyDown", .keyDown), ("keyUp", .keyUp), ("data", .data),
        ("initialize", .initialize), ("press", .press), ("release", .release),
        ("releaseOutside", .releaseOutside), ("rollOver", .rollOver), ("rollOut", .rollOut),
        ("dragOver", .dragOver), ("dragOut", .dragOut), ("keyPress", .keyPress),
        ("construct", .construct)
    ]

    /// Records one movie's action side: every DoAction block (main timeline
    /// and every sprite), every CLIPACTIONS handler, and every DoInitAction
    /// block, in the stable order `SWFMovie.actionBlocks` documents.
    mutating func record(_ movie: SWFMovie, path: String) {
        var walk = SWFActionTimelineWalk()
        walk.add(movie.timeline)
        for characterId in movie.characters.keys.sorted() {
            if case let .sprite(sprite) = movie.characters[characterId] {
                walk.add(sprite.timeline)
            }
        }
        doActionBlockCount += walk.doActionBlockCount
        clipActionBlockCount += walk.clipRecords.count
        doInitActionBlockCount += movie.initActions.count
        recordClipEvents(walk.clipRecords, path: path)

        var movieOpcodes: Set<UInt8> = []
        for block in movie.actionBlocks {
            processBlock(block, path: path, movieOpcodes: &movieOpcodes)
        }

        movies.append(
            SWFActionMovieSummary(
                path: path,
                actionBlocks: movie.tally.actionBlocks,
                actionRecords: movie.tally.actionRecords,
                distinctOpcodes: movieOpcodes.count,
                unknownOpcodes: movie.tally.unknownActionOpcodes,
                undecodedOpcodes: movie.tally.undecodedActionOpcodes,
                warnings: movie.tally.actionWarnings
            )
        )
    }

    private mutating func processBlock(
        _ block: SWFActionBlock,
        path: String,
        movieOpcodes: inout Set<UInt8>
    ) {
        maxBlockBytes = max(maxBlockBytes, block.byteCount)
        maxBlockRecords = max(maxBlockRecords, block.records.count)
        var pool: [String] = []
        for (index, record) in block.records.enumerated() {
            recordOpcode(record, path: path, movieOpcodes: &movieOpcodes)
            recordStructure(record)
            if case let .constantPool(strings) = record.operands {
                pool = strings
                constantPoolCount += 1
                maxConstantPoolSize = max(maxConstantPoolSize, strings.count)
            }
            if index > 0, Self.hostAPICodes.contains(record.code) {
                recordHostAPIName(preceding: block.records[index - 1], pool: pool, path: path)
            }
        }
    }

    private mutating func recordOpcode(
        _ record: SWFActionRecord,
        path: String,
        movieOpcodes: inout Set<UInt8>
    ) {
        opcodeCounts[record.code, default: 0] += 1
        opcodeMovies[record.code, default: []].insert(path)
        movieOpcodes.insert(record.code)
        if !SWFActionName.isKnown(record.code) {
            unknownOpcodeMovies[record.code, default: []].insert(path)
        }
    }

    private mutating func recordStructure(_ record: SWFActionRecord) {
        switch record.operands {
        case let .defineFunction(function) where record.code == 0x8E:
            defineFunction2Count += 1
            maxRegisterCount = max(maxRegisterCount, function.registerCount)
        case .defineFunction:
            defineFunctionCount += 1
        case .with:
            withCount += 1
        case .tryBlock:
            tryCount += 1
        default:
            break
        }
    }

    private mutating func recordHostAPIName(
        preceding: SWFActionRecord,
        pool: [String],
        path: String
    ) {
        guard
            case let .push(values) = preceding.operands,
            let last = values.last,
            let name = Self.resolvedName(last, pool: pool)
        else {
            return
        }
        hostNameCounts[name, default: 0] += 1
        hostNameMovies[name, default: []].insert(path)
    }

    private static func resolvedName(_ value: SWFActionValue, pool: [String]) -> String? {
        switch value {
        case let .string(text):
            text
        case let .constant8(index):
            pool.indices.contains(Int(index)) ? pool[Int(index)] : nil
        case let .constant16(index):
            pool.indices.contains(Int(index)) ? pool[Int(index)] : nil
        default:
            nil
        }
    }

    private mutating func recordClipEvents(_ records: [SWFClipActionRecord], path: String) {
        for record in records {
            for entry in Self.clipEventTable where record.events.contains(entry.flag) {
                clipEventCounts[entry.name, default: 0] += 1
                clipEventMovies[entry.name, default: []].insert(path)
            }
        }
    }
}

/// Walks a timeline's frames once, counting DoAction blocks and collecting
/// every CLIPACTIONS handler record so clip-event usage and block-kind counts
/// can be tallied without re-walking the movie.
private struct SWFActionTimelineWalk {
    private(set) var doActionBlockCount = 0
    private(set) var clipRecords: [SWFClipActionRecord] = []

    mutating func add(_ timeline: SWFTimeline) {
        for frame in timeline.frames {
            doActionBlockCount += frame.actions.count
            for step in frame.steps {
                guard
                    case let .place(placement) = step,
                    let clip = placement.clipActions
                else {
                    continue
                }
                clipRecords.append(contentsOf: clip.records)
            }
        }
    }
}
