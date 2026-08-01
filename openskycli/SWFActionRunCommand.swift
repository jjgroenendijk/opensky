// `swf action-run`: bring one vanilla movie up through `SWFMovieRuntime`, tick
// it, and print what came out — faults, unimplemented opcodes, the missing-API
// tally, registered classes, `GameDelegate` callbacks and the display tree.
//
// This is the probe every menu bring-up needs (M8.5.1 ran it by hand for
// `startmenu.swf`, M12.2.2 for `inventorymenu.swf`), promoted to a subcommand
// so the next one does not rewrite it. It only parses args and prints; the
// runtime it drives lives in `opensky/Formats/SWF/Runtime/`.

import Foundation

enum SWFActionRunCommand {
    private static let defaultTicks = 10
    private static let defaultMissingLimit = 40
    private static let defaultTreeDepth = 4

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let filter = try scanner.option("--movie")?.lowercased()
        let ticks = try positiveOption(scanner.option("--ticks"), name: "--ticks")
            ?? defaultTicks
        let missingLimit = try positiveOption(scanner.option("--limit"), name: "--limit")
            ?? defaultMissingLimit
        let treeDepth = try positiveOption(scanner.option("--tree-depth"), name: "--tree-depth")
            ?? defaultTreeDepth
        let callName = try scanner.option("--call")
        let dumpPath = try scanner.option("--dump")
        try scanner.finish()

        let vfs = context.makeFileSystem()
        let loader = SWFMovieLoader(fileSystem: vfs)
        let paths = loader.moviePaths().filter { filter.map($0.contains) ?? true }
        guard let path = paths.first else {
            throw CLIError.failure("no interface\\*.swf movies matched")
        }
        guard paths.count == 1 else {
            throw CLIError.failure(
                "--movie matched \(paths.count) movies: \(paths.joined(separator: ", "))"
            )
        }

        let runtime = try SWFMovieRuntime(movieScene: loader.load(path: path))
        runtime.start()
        if let callName {
            for name in callName.split(separator: ",") {
                runtime.callMovie(String(name))
            }
        }
        for _ in 0 ..< ticks {
            runtime.advance()
        }
        printReport(
            runtime,
            path: path,
            ticks: ticks,
            missingLimit: missingLimit,
            treeDepth: treeDepth
        )
        for target in dumpPath?.split(separator: ",") ?? [] {
            printDump(runtime, path: String(target))
        }
    }

    private static func positiveOption(_ text: String?, name: String) throws -> Int? {
        guard let text else { return nil }
        guard let value = Int(text), value > 0 else {
            throw CLIError.usage("\(name) needs a positive integer")
        }
        return value
    }
}

// MARK: - Section printers

extension SWFActionRunCommand {
    private static func printReport(
        _ runtime: SWFMovieRuntime,
        path: String,
        ticks: Int,
        missingLimit: Int,
        treeDepth: Int
    ) {
        let tally = runtime.tally
        print(
            "[INFO] swf action-run \(path): \(ticks) ticks, \(runtime.nodeCount) nodes, "
                + "\(tally.faultTotal) faults, \(tally.unimplementedTotal) unimplemented opcodes, "
                + "\(tally.missingNames.count) distinct missing names "
                + "(\(tally.missingTotal) hits)"
        )
        printFaults(tally)
        printPlacements(runtime.movie)
        printMissing(tally, limit: missingLimit)
        printClasses(runtime)
        printCallbacks(runtime)
        printInvokeLog(runtime)
        printTree(runtime.root, depth: treeDepth)
    }

    private static func printFaults(_ tally: AS2Tally) {
        var byKind: [String: Int] = [:]
        for fault in tally.faults {
            byKind[fault.kind, default: 0] += 1
        }
        let summary = byKind.sorted { $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        print("[INFO] swf action-run faults: \(summary.isEmpty ? "none" : summary)")
    }

    /// Placements whose character id the movie's own dictionary does not hold.
    /// Those come from `ImportAssets2` and instantiate as nothing, which is a
    /// missing child clip rather than a fault — so nothing else would report it.
    private static func printPlacements(_ movie: SWFMovie) {
        var timelines = [movie.timeline]
        for id in movie.characters.keys.sorted() {
            if case let .sprite(sprite) = movie.characters[id] {
                timelines.append(sprite.timeline)
            }
        }
        var unresolved: [UInt16: String] = [:]
        var placements = 0
        for timeline in timelines {
            for frame in timeline.frames {
                for case let .place(placement) in frame.steps {
                    placements += 1
                    guard
                        let id = placement.characterId, movie.characters[id] == nil
                    else { continue }
                    unresolved[id] = placement.name ?? movie.importedNames[id] ?? "?"
                }
            }
        }
        print(
            "[INFO] swf action-run placements: \(placements) total, "
                + "\(unresolved.count) unresolved character ids, "
                + "\(movie.importedNames.count) imported names"
        )
        print("[INFO] swf action-run import merge: \(movie.importDiagnostics.summary)")
        for path in movie.importDiagnostics.mergedPaths {
            print("[INFO]   merged \(path)")
        }
        for (id, name) in unresolved.sorted(by: { $0.key < $1.key }) {
            print("[INFO]   unresolved character \(id) as \"\(name)\"")
        }
        for imported in movie.imports {
            let names = imported.assets.map { "\($0.characterId) \($0.name)" }
                .joined(separator: ", ")
            print("[INFO]   imports from \(imported.url): \(names)")
        }
    }

    private static func printMissing(_ tally: AS2Tally, limit: Int) {
        let ranked = tally.rankedMissing.prefix(limit)
        print(
            "[INFO] swf action-run missing: \(tally.missingNames.count) distinct, "
                + "top \(ranked.count) shown"
        )
        for entry in ranked {
            print("[INFO]   \(entry.name) \(entry.count)")
        }
    }

    private static func printClasses(_ runtime: SWFMovieRuntime) {
        let names = runtime.runtime.registeredClassNames.sorted()
        print("[INFO] swf action-run classes: \(names.count) registered")
        for name in names {
            print("[INFO]   \(name)")
        }
    }

    private static func printCallbacks(_ runtime: SWFMovieRuntime) {
        let names = runtime.movieCallbackNames.sorted()
        print("[INFO] swf action-run callbacks: \(names.count) GameDelegate names")
        for name in names {
            print("[INFO]   \(name)")
        }
    }

    private static func printInvokeLog(_ runtime: SWFMovieRuntime) {
        let log = runtime.invokeLog
        print(
            "[INFO] swf action-run invokes: \(log.total) total, "
                + "\(log.unhandled) unhandled, \(log.dropped) dropped"
        )
        for entry in log.entries where !entry.isHandled {
            print(
                "[INFO]   unhandled \(entry.direction.rawValue) \(entry.name)(\(entry.arguments))"
            )
        }
    }

    /// The display tree by instance path, which is what a bridge addresses
    /// nodes with (`runtime.node(atPath:from:)`).
    private static func printTree(_ root: SWFDisplayObject, depth: Int) {
        print("[INFO] swf action-run tree: depth \(depth)")
        printNode(root, prefix: "", remaining: depth)
    }

    private static func printNode(_ node: SWFDisplayObject, prefix: String, remaining: Int) {
        guard remaining > 0 else { return }
        for child in node.children {
            let name = child.name ?? "?depth\(child.depth)"
            let path = "\(prefix)/\(name)"
            print("[INFO]   \(path)\(frameSummary(of: child))")
            printNode(child, prefix: path, remaining: remaining - 1)
        }
    }

    private static func frameSummary(of node: SWFDisplayObject) -> String {
        guard let timeline = node.timeline else { return "" }
        let labels = timeline.frameLabels
        let labelText = labels.isEmpty ? "" : " labels [\(labels.joined(separator: " "))]"
        return " frame \(node.currentFrame + 1)/\(node.frameCount)\(labelText)"
    }

    /// The own properties of one display node's `AS2Object`, which is how a
    /// bridge finds out what a menu class actually built.
    private static func printDump(_ runtime: SWFMovieRuntime, path: String) {
        guard let node = runtime.node(atPath: path, from: runtime.root) else {
            print("[INFO] swf action-run dump \(path): no such node")
            return
        }
        let names = node.object.ownPropertyNames
        print("[INFO] swf action-run dump \(path): \(names.count) own properties")
        for name in names.sorted() {
            let value = node.object.lookup(name)?.property.value
            print("[INFO]   \(name) = \(describe(value))")
        }
    }

    private static func describe(_ value: AS2Value?) -> String {
        switch value {
        case nil, .undefined: "undefined"
        case .null: "null"
        case let .boolean(flag): "\(flag)"
        case let .number(number): "\(number)"
        case let .string(text): "\"\(text)\""
        case let .object(object):
            object.callable == nil
                ? "object(\(object.ownPropertyNames.count) props)"
                : "function"
        }
    }
}
