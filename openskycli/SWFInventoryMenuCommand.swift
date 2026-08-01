// `swf inventory-menu`: drive `interface\inventorymenu.swf` through
// `InventoryMenuMovieBridge` with a real player inventory and report what the
// movie built (M12.2.2, issue #289).
//
// This is the bring-up gate for the menu's data contract, in the CLI rather
// than only in a test because the real-data XCTest host is unreliable on this
// machine (docs/tools/environment.md). It only parses args and prints; the
// bridge and the row list it publishes live in `opensky/UI/` and are unit
// tested there against synthetic fixtures.

import Foundation

enum SWFInventoryMenuCommand {
    private static let defaultTicks = 20

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let ticks = try positive(scanner.option("--ticks"), name: "--ticks") ?? defaultTicks
        let downCount = try positive(scanner.option("--down"), name: "--down") ?? 0
        let rightCount = try positive(scanner.option("--right"), name: "--right") ?? 0
        try scanner.finish()

        let vfs = context.makeFileSystem()
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: vfs)
                .load(path: InventoryMenuMovieBridge.moviePath)
        )
        InventoryMenuMovieBridge.prepare(runtime: runtime)
        runtime.start()
        InventoryMenuMovieBridge.activate(runtime: runtime) { _ in }
        for _ in 0 ..< ticks {
            runtime.advance()
        }

        var model = try makeModel(context: context)
        InventoryMenuMovieBridge.publish(model, runtime: runtime)
        runtime.advance()
        printState(runtime, model: model, stage: "published")

        for _ in 0 ..< rightCount {
            drive(.move(.right), runtime: runtime, model: &model)
        }
        for _ in 0 ..< downCount {
            drive(.move(.down), runtime: runtime, model: &model)
        }
        if downCount > 0 || rightCount > 0 {
            printState(runtime, model: model, stage: "navigated")
        }
        printDiagnostics(runtime)
    }

    /// The player's real inventory, which is empty until something puts items
    /// in it, so the probe seeds it from the plugin's own item index instead —
    /// one stack of each of the first few carryable forms. Nothing is written
    /// to the install; the inventory lives in an in-memory `WorldStateStore`.
    @MainActor
    private static func makeModel(context: CLIContext) throws -> InventoryMenuModel {
        let baselines = try InventoryBaselineResolver.build(from: context.loadSkyrimESM())
        let inventory = InventoryRuntime(store: WorldStateStore(), baselines: baselines)
        for family in ItemDefinition.Family.allCases {
            for definition in baselines.items.definitions(of: family).prefix(3) {
                try? inventory.add(definition.formID, count: 2, to: .player)
            }
        }
        try? inventory.add(InventoryRuntime.vanillaGoldFormID, count: 137, to: .player)
        return InventoryMenuModel.build(holder: .player, runtime: inventory)
    }

    private static func drive(
        _ event: MenuInputEvent,
        runtime: SWFMovieRuntime,
        model: inout InventoryMenuModel
    ) {
        if case let .move(direction) = event, direction == .left || direction == .right {
            model.moveCategory(by: direction == .right ? 1 : -1)
            InventoryMenuMovieBridge.publish(model, runtime: runtime)
            runtime.advance()
            return
        }
        guard InventoryMenuMovieBridge.handle(event, runtime: runtime) else {
            print("[WARNING] swf inventory-menu: the movie declined \(event)")
            return
        }
        if let index = InventoryMenuMovieBridge.selectedCategoryIndex(runtime: runtime) {
            model.selectCategory(index)
        }
        if let index = InventoryMenuMovieBridge.selectedIndex(runtime: runtime) {
            model.select(index)
        }
        InventoryMenuMovieBridge.publish(model, runtime: runtime)
        runtime.advance()
    }

    private static func positive(_ text: String?, name: String) throws -> Int? {
        guard let text else { return nil }
        guard let value = Int(text), value >= 0 else {
            throw CLIError.usage("\(name) needs a non-negative integer")
        }
        return value
    }
}

// MARK: - Reporting

extension SWFInventoryMenuCommand {
    private static func printState(
        _ runtime: SWFMovieRuntime,
        model: InventoryMenuModel,
        stage: String
    ) {
        let categories = InventoryMenuMovieBridge.categoryLabels(runtime: runtime)
        let rows = InventoryMenuMovieBridge.entryLabels(runtime: runtime)
        print(
            "[INFO] swf inventory-menu \(stage): \(categories.count) movie categories, "
                + "\(rows.count) movie rows, engine has \(model.categories.count) and "
                + "\(model.entries.count)"
        )
        print("[INFO]   movie categories: \(categories.joined(separator: ", "))")
        print("[INFO]   movie rows: \(rows.prefix(12).joined(separator: ", "))")
        let category = InventoryMenuMovieBridge.selectedCategoryIndex(runtime: runtime)
        let row = InventoryMenuMovieBridge.selectedIndex(runtime: runtime)
        print(
            "[INFO]   movie selection: category \(category.map(String.init) ?? "none"), "
                + "row \(row.map(String.init) ?? "none")"
        )
        print(
            "[INFO]   engine selection: category \(model.selectedCategoryIndex) "
                + "(\(model.categoryLabels[safe: model.selectedCategoryIndex] ?? "?")), "
                + "row \(model.selectedIndex) "
                + "(\(model.selectedEntry?.name ?? "none"))"
        )
    }

    private static func printDiagnostics(_ runtime: SWFMovieRuntime) {
        let diagnostics = InventoryMenuMovieBridge.diagnostics(runtime: runtime)
        print(
            "[INFO] swf inventory-menu diagnostics: \(runtime.nodeCount) nodes, "
                + "\(diagnostics.faults) faults, "
                + "\(runtime.tally.unimplementedTotal) unimplemented opcodes, "
                + "\(diagnostics.unhandledInvokes) unhandled of "
                + "\(runtime.invokeLog.total) invokes, "
                + "\(diagnostics.missingNames) distinct missing names"
        )
        for entry in runtime.tally.rankedMissing.prefix(20) {
            print("[INFO]   missing \(entry.name) \(entry.count)")
        }
        for entry in runtime.invokeLog.entries where !entry.isHandled {
            print("[INFO]   unhandled \(entry.direction.rawValue) \(entry.name)")
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
