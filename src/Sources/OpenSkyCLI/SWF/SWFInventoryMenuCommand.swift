// `menu inventory`: drive `inventorymenu.swf` through
// `InventoryMenuMovieBridge` with a real inventory. A CLI gate because the
// real-data XCTest host is unreliable here (docs/tools/environment.md).

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyWorldState

enum SWFInventoryMenuCommand {
    static func run(context: CLIContext, arguments: MenuArguments.Inventory) throws {
        let ticks = arguments.drive.ticks
        let downCount = arguments.drive.down
        let rightCount = arguments.right

        let vfs = context.makeFileSystem()
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: vfs)
                .load(path: InventoryMenuMovieBridge.moviePath)
        )
        InventoryMenuMovieBridge.prepare(runtime: runtime)
        runtime.start()
        InventoryMenuMovieBridge.activate(runtime: runtime) { action in
            print("[INFO] menu inventory action: \(action)")
        }
        for _ in 0 ..< ticks {
            runtime.advance()
        }

        var model = try makeModel(context: context)
        ItemCardSubMenuBridge.showItemsList(runtime: runtime)
        InventoryMenuMovieBridge.publish(model, runtime: runtime)
        for _ in 0 ..< ticks {
            runtime.advance()
        }
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
        if arguments.drop {
            drop(arguments, runtime: runtime, model: model)
        }
        printDiagnostics(runtime)
    }

    /// The player's real inventory, which is empty until something puts items
    /// in it, so the probe seeds it from the plugin's own item index instead —
    /// a few stacks of the first carryable forms of each family. Nothing is written
    /// to the install; the inventory lives in an in-memory `WorldStateStore`.
    @MainActor
    private static func makeModel(context: CLIContext) throws -> InventoryMenuModel {
        let baselines = try InventoryBaselineResolver.build(from: context.loadOrder().plugins)
        let inventory = InventoryRuntime(store: WorldStateStore(), baselines: baselines)
        for family in ItemDefinition.Family.allCases {
            // The first stack is above the quantity slider's limit, so `--drop` opens it.
            for (index, definition) in baselines.items.definitions(of: family).prefix(3)
                .enumerated()
            {
                _ = try? inventory.add(definition.formID, count: index == 0 ? 12 : 2, to: .player)
            }
        }
        _ = try? inventory.add(InventoryRuntime.vanillaGoldFormID, count: 137, to: .player)
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
            print("[WARNING] menu inventory: the movie declined \(event)")
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
}

// MARK: - Drop

extension SWFInventoryMenuCommand {
    /// Presses drop, moves the slider, then accepts or cancels it, and prints the
    /// item-card calls the movie made.
    private static func drop(
        _ arguments: MenuArguments.Inventory,
        runtime: SWFMovieRuntime,
        model: InventoryMenuModel
    ) {
        let start = runtime.invokeLog.total
        let entry = model.selectedEntry
        print(
            "[INFO] menu inventory drop: \(entry?.name ?? "no row") ×\(entry?.count ?? 0), "
                + "limit \(InventoryQuantityPrompt.countLimit)"
        )
        guard InventoryMenuMovieBridge.requestDrop(runtime: runtime) else {
            print("[WARNING] menu inventory: the movie has no DropItem callback")
            return
        }
        runtime.advance()
        let step: MenuInputEvent = arguments.quantity < 0 ? .move(.left) : .move(.right)
        for _ in 0 ..< abs(arguments.quantity) {
            ItemCardSubMenuBridge.handle(step, runtime: runtime)
            runtime.advance()
        }
        let finish: MenuInputEvent = arguments.cancel ? .button(.cancel) : .button(.accept)
        ItemCardSubMenuBridge.handle(finish, runtime: runtime)
        runtime.advance()
        let names: Set = [
            InventoryMenuMovieBridge.dropCallback, "ShowQuantityMenu", "ItemDrop",
            "QuantitySliderOpen", "UpdateItem3D"
        ]
        let recorded = runtime.invokeLog.total - start
        for call in runtime.invokeLog.entries.suffix(recorded) where names.contains(call.name) {
            print("[INFO]   \(call.direction.rawValue) \(call.name)(\(call.arguments))")
        }
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
            "[INFO] menu inventory \(stage): \(categories.count) movie categories, "
                + "\(rows.count) movie rows, engine has \(model.categories.count) and "
                + "\(model.entries.count)"
        )
        print("[INFO]   movie categories: \(categories.joined(separator: ", "))")
        let state = ItemCardSubMenuBridge.listsState(runtime: runtime).map(String.init) ?? "none"
        print("[INFO]   movie lists state: \(state)")
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
            "[INFO] menu inventory diagnostics: \(runtime.nodeCount) nodes, "
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
