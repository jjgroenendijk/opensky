// `swf action-sweep`: the milestone 8.3.1 stage-2 gate. Parses every vanilla
// `interface\*.swf` movie, decodes its full action side (main timeline,
// sprites, DoInitAction, CLIPACTIONS) through `SWFActionInventory`, and prints
// the opcode/host-API/clip-event/structure inventory the 8.3.1 decision doc
// (`docs/decisions/swf-as2-scope.md`) draws its numbers from. This command
// only parses args and prints; the tallying lives in
// `opensky/Formats/SWF/SWFActionInventory.swift` and is unit-tested there.

import Foundation

enum SWFActionSweep {
    private static let defaultHostAPILimit = 120
    /// `SWFClipEventFlags` case names in bit order, so the report is
    /// deterministic rather than sorted by (possibly zero) count.
    private static let clipEventOrder = [
        "load", "enterFrame", "unload", "mouseMove", "mouseDown", "mouseUp",
        "keyDown", "keyUp", "data", "initialize", "press", "release",
        "releaseOutside", "rollOver", "rollOut", "dragOver", "dragOut",
        "keyPress", "construct"
    ]

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        // Substring filter mirrors `swf render-sweep --movie`.
        let filter = try scanner.option("--movie")?.lowercased()
        let limit = try parseLimit(scanner.option("--limit"))
        try scanner.finish()

        let vfs = context.makeFileSystem()
        let paths = SWFMovieLoader(fileSystem: vfs).moviePaths()
            .filter { filter.map($0.contains) ?? true }
        guard !paths.isEmpty else {
            throw CLIError.failure("no interface\\*.swf movies matched")
        }

        var inventory = SWFActionInventory()
        var failures: [String] = []
        for path in paths {
            do {
                let movie = try SWFMovie(file: SWFFile(data: vfs.contents(forPath: path)))
                inventory.record(movie, path: path)
                if let summary = inventory.movies.last {
                    printMovieLine(summary)
                }
            } catch {
                failures.append(path)
                printError("[ERROR] \(path): \(String(describing: error))")
            }
        }

        printReport(inventory, limit: limit)
        print("[INFO] swf action-sweep: \(paths.count) movies, \(failures.count) failed")
        guard failures.isEmpty else {
            throw CLIError.failure(
                "swf action-sweep failed: \(failures.count) movies did not decode"
            )
        }
    }

    private static func parseLimit(_ text: String?) throws -> Int {
        guard let text else {
            return defaultHostAPILimit
        }
        guard let value = Int(text), value > 0 else {
            throw CLIError.usage("--limit needs a positive integer")
        }
        return value
    }

    private static func printMovieLine(_ summary: SWFActionMovieSummary) {
        print(
            "[INFO] \(summary.path): \(summary.actionBlocks) action blocks, "
                + "\(summary.actionRecords) action records, "
                + "\(summary.distinctOpcodes) distinct opcodes, "
                + "\(summary.unknownOpcodes) unknown, \(summary.undecodedOpcodes) undecoded, "
                + "\(summary.warnings) warnings"
        )
    }

    private static func printReport(_ inventory: SWFActionInventory, limit: Int) {
        printOpcodeFrequency(inventory)
        printUnknownOpcodes(inventory)
        printHostAPI(inventory, limit: limit)
        printClipEvents(inventory)
        printStructure(inventory)
        printRanking(inventory)
    }

    private static func hex(_ code: UInt8) -> String {
        String(format: "0x%02x", code)
    }
}

// MARK: - Section printers

extension SWFActionSweep {
    /// Section 1: every opcode observed, descending by count — the coverage
    /// tally the milestone gate requires.
    private static func printOpcodeFrequency(_ inventory: SWFActionInventory) {
        let totalRecords = inventory.opcodeCounts.values.reduce(0, +)
        print(
            "[INFO] swf action-sweep opcodes: \(totalRecords) records, "
                + "\(inventory.distinctOpcodeCount) distinct opcodes"
        )
        let ordered = inventory.opcodeCounts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        for (code, count) in ordered {
            let name = SWFActionName.name(forCode: code) ?? "unknown"
            let movies = inventory.opcodeMovies[code]?.count ?? 0
            print("[INFO]   \(hex(code)) \(name) \(count) \(movies)")
        }
    }

    /// Section 2: codes absent from `SWFActionName` — expect zero on vanilla.
    private static func printUnknownOpcodes(_ inventory: SWFActionInventory) {
        guard !inventory.unknownOpcodeMovies.isEmpty else {
            print("[INFO] swf action-sweep unknown: 0 unknown opcodes")
            return
        }
        print(
            "[INFO] swf action-sweep unknown: "
                + "\(inventory.unknownOpcodeMovies.count) unknown opcodes"
        )
        let ordered = inventory.unknownOpcodeMovies.sorted { $0.key < $1.key }
        for (code, movies) in ordered {
            let count = inventory.opcodeCounts[code] ?? 0
            let names = movies.sorted().joined(separator: ", ")
            print("[INFO]   \(hex(code)) \(count) occurrences in \(movies.count) movies: \(names)")
        }
    }

    /// Section 3: member/function/method names structurally resolved from the
    /// immediately preceding `ActionPush` — the GFx host API surface.
    private static func printHostAPI(_ inventory: SWFActionInventory, limit: Int) {
        print(
            "[INFO] swf action-sweep hostapi: \(inventory.distinctHostNameCount) distinct names, "
                + "top \(limit) shown"
        )
        let ordered = inventory.hostNameCounts.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        for (name, count) in ordered.prefix(limit) {
            let movies = inventory.hostNameMovies[name]?.count ?? 0
            print("[INFO]   \(name) \(count) \(movies)")
        }
    }

    /// Section 4: CLIPACTIONS handler events, fixed bit order (zero shown
    /// explicitly rather than omitted).
    private static func printClipEvents(_ inventory: SWFActionInventory) {
        let totalFlags = inventory.clipEventCounts.values.reduce(0, +)
        print(
            "[INFO] swf action-sweep clipevents: \(inventory.clipActionBlockCount) handlers, "
                + "\(totalFlags) event flags set"
        )
        for name in clipEventOrder {
            let count = inventory.clipEventCounts[name] ?? 0
            let movies = inventory.clipEventMovies[name]?.count ?? 0
            print("[INFO]   \(name) \(count) \(movies)")
        }
    }

    /// Section 5: function/block structure stats.
    private static func printStructure(_ inventory: SWFActionInventory) {
        print(
            "[INFO] swf action-sweep structure: DefineFunction \(inventory.defineFunctionCount), "
                + "DefineFunction2 \(inventory.defineFunction2Count), "
                + "max registers \(inventory.maxRegisterCount), With \(inventory.withCount), "
                + "Try \(inventory.tryCount), ConstantPool \(inventory.constantPoolCount) "
                + "(max size \(inventory.maxConstantPoolSize)), "
                + "largest block \(inventory.maxBlockBytes) bytes / "
                + "\(inventory.maxBlockRecords) records"
        )
        print(
            "[INFO] swf action-sweep structure blocks: "
                + "DoAction \(inventory.doActionBlockCount), "
                + "DoInitAction \(inventory.doInitActionBlockCount), "
                + "ClipActions \(inventory.clipActionBlockCount)"
        )
    }

    /// Section 6: the movies most worth targeting first, by action-record
    /// volume.
    private static func printRanking(_ inventory: SWFActionInventory) {
        let ranked = inventory.movies.sorted { $0.actionRecords > $1.actionRecords }.prefix(20)
        print("[INFO] swf action-sweep ranking: top \(ranked.count) movies by action records")
        for (index, summary) in ranked.enumerated() {
            print(
                "[INFO]   \(index + 1). \(summary.path) \(summary.actionRecords) records, "
                    + "\(summary.actionBlocks) blocks"
            )
        }
    }
}
