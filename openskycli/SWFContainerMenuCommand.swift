// `swf container-menu`: drive `interface\containermenu.swf` or
// `interface\bartermenu.swf` through `ContainerMenuMovieBridge` against a real
// container and a real player inventory, and report what the movie built
// (M12.2.3, issue #179).
//
// The bring-up gate for both menus' data contract, in the CLI rather than only
// in a test because the real-data XCTest host is unreliable on this machine
// (docs/tools/environment.md). It only parses args and prints: the bridge, the
// two-pane list and the pricing all live in `opensky/` and are unit tested
// there against synthetic fixtures.

import Foundation

enum SWFContainerMenuCommand {
    private static let defaultTicks = 20
    /// How many of the plugin's own item forms seed each side.
    private static let seedPerFamily = 3
    private static let seedCount: Int32 = 2
    private static let playerSeedGold: Int32 = 5000
    private static let merchantSeedGold: Int32 = 800

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let mode = try mode(scanner.option("--mode"))
        let side = try side(scanner.option("--side"))
        let ticks = try positive(scanner.option("--ticks"), name: "--ticks") ?? defaultTicks
        let downCount = try positive(scanner.option("--down"), name: "--down") ?? 0
        let transfers = try positive(scanner.option("--transfer"), name: "--transfer") ?? 0
        try scanner.finish()

        let vfs = context.makeFileSystem()
        let runtime = try SWFMovieRuntime(
            movieScene: SWFMovieLoader(fileSystem: vfs)
                .load(path: ContainerMenuMovieBridge.moviePath(for: mode))
        )
        ContainerMenuMovieBridge.prepare(runtime: runtime)
        runtime.start()
        ContainerMenuMovieBridge.activate(runtime: runtime, mode: mode) { _ in }
        for _ in 0 ..< ticks {
            runtime.advance()
        }

        let world = try makeWorld(context: context, mode: mode)
        var model = world.model
        model.select(side: side)
        ContainerMenuMovieBridge.publish(model, runtime: runtime)
        runtime.advance()
        printState(runtime, model: model, stage: "published")

        for _ in 0 ..< downCount {
            drive(.move(.down), runtime: runtime, model: &model)
        }
        if downCount > 0 {
            printState(runtime, model: model, stage: "navigated")
        }
        for _ in 0 ..< transfers {
            transfer(world: world, model: &model, runtime: runtime)
        }
        if transfers > 0 {
            printState(runtime, model: model, stage: "traded")
        }
        printDiagnostics(runtime, mode: mode, model: model)
    }

    private static func mode(_ text: String?) throws -> ContainerMenuModel.Mode {
        switch text {
        case nil, "container": .container
        case "barter": .barter
        default: throw CLIError.usage("--mode takes container or barter")
        }
    }

    private static func side(_ text: String?) throws -> ContainerMenuModel.Side {
        switch text {
        case nil, "container": .container
        case "player": .player
        default: throw CLIError.usage("--side takes container or player")
        }
    }

    // MARK: - World

    /// The engine side of the probe: an in-memory store holding a seeded player
    /// inventory and a seeded container, plus the barter pricing read out of the
    /// install's own GMST records. Nothing is written to the install.
    struct ProbeWorld {
        let items: WorldItemRuntime
        let container: InventoryHolder
        let session: BarterSession
        var model: ContainerMenuModel
    }

    @MainActor
    private static func makeWorld(
        context: CLIContext,
        mode: ContainerMenuModel.Mode
    ) throws -> ProbeWorld {
        let file = try context.loadSkyrimESM()
        let baselines = try InventoryBaselineResolver.build(from: file)
        let inventory = InventoryRuntime(store: WorldStateStore(), baselines: baselines)
        let items = WorldItemRuntime(inventory: inventory)
        // `.generated` rather than `.container(base:)`: the probe's merchant is
        // an in-memory reference with no CONT record behind it, and a generated
        // owner is exactly the one whose baseline is empty by definition.
        let container = InventoryHolder(
            key: inventory.store.allocateGeneratedKey(),
            owner: .generated,
            cell: nil
        )
        try seed(inventory: inventory, baselines: baselines, container: container)
        let pricing = BarterPricing.resolve(
            store: GameSettingLoader.load(root: context.root, baseFile: file)
        )
        print("[INFO] swf container-menu pricing: \(describe(pricing))")
        return ProbeWorld(
            items: items,
            container: container,
            session: BarterSession(runtime: items, merchant: container, pricing: pricing),
            model: ContainerMenuModel.build(
                container: container,
                containerName: "Probe merchant",
                mode: mode,
                pricing: pricing,
                runtime: inventory
            )
        )
    }

    /// One stack of each of the first few carryable forms per family on both
    /// sides, plus gold, so both panes and both directions of trade have
    /// something in them.
    @MainActor
    private static func seed(
        inventory: InventoryRuntime,
        baselines: InventoryBaselineResolver,
        container: InventoryHolder
    ) throws {
        for family in ItemDefinition.Family.allCases {
            for definition in baselines.items.definitions(of: family).prefix(seedPerFamily) {
                try? inventory.add(definition.formID, count: seedCount, to: .player)
                try? inventory.add(definition.formID, count: seedCount, to: container)
            }
        }
        try inventory.add(InventoryRuntime.vanillaGoldFormID, count: playerSeedGold, to: .player)
        try inventory.add(
            InventoryRuntime.vanillaGoldFormID, count: merchantSeedGold, to: container
        )
    }

    /// Buys or sells the selected row, whichever side the model is on, and
    /// republishes. Container mode takes or stores instead.
    @MainActor
    private static func transfer(
        world: ProbeWorld,
        model: inout ContainerMenuModel,
        runtime: SWFMovieRuntime
    ) {
        guard let entry = model.selectedEntry else {
            print("[WARNING] swf container-menu: nothing selected to transfer")
            return
        }
        do {
            let outcome = try apply(entry, world: world, model: model)
            print("[INFO] swf container-menu \(outcome)")
        } catch {
            print("[INFO] swf container-menu refused: \(String(describing: error))")
        }
        var rebuilt = ContainerMenuModel.build(
            container: world.container,
            containerName: model.containerName,
            mode: model.mode,
            pricing: model.pricing,
            runtime: world.items.inventory
        )
        rebuilt.restore(from: model)
        model = rebuilt
        ContainerMenuMovieBridge.publish(model, runtime: runtime)
        runtime.advance()
    }

    @MainActor
    private static func apply(
        _ entry: InventoryMenuEntry,
        world: ProbeWorld,
        model: ContainerMenuModel
    ) throws -> String {
        switch (model.mode, model.side) {
        case (.barter, .container):
            let bought = try world.session.buy(entry.item)
            return "bought \(entry.name) for \(bought.gold) gold"
        case (.barter, .player):
            let sold = try world.session.sell(entry.item)
            return "sold \(entry.name) for \(sold.gold) gold"
        case (.container, .container):
            try world.items.inventory.transfer(
                entry.item, count: 1, from: world.container, to: .player
            )
            return "took \(entry.name)"
        case (.container, .player):
            try world.items.inventory.transfer(
                entry.item, count: 1, from: .player, to: world.container
            )
            return "stored \(entry.name)"
        }
    }

    private static func drive(
        _ event: MenuInputEvent,
        runtime: SWFMovieRuntime,
        model: inout ContainerMenuModel
    ) {
        guard ContainerMenuMovieBridge.handle(event, runtime: runtime) else {
            print("[WARNING] swf container-menu: the movie declined \(event)")
            return
        }
        if let index = ContainerMenuMovieBridge.selectedIndex(runtime: runtime) {
            model.select(index)
        }
        ContainerMenuMovieBridge.publish(model, runtime: runtime)
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

extension SWFContainerMenuCommand {
    private static func describe(_ pricing: BarterPricing) -> String {
        String(
            format: "speech %.0f, factor %.4f, buy x%.4f, sell x%.4f (%@)",
            pricing.speechSkill,
            pricing.basePriceFactor,
            pricing.basePriceFactor,
            1 / pricing.basePriceFactor,
            pricing.source
        )
    }

    private static func printState(
        _ runtime: SWFMovieRuntime,
        model: ContainerMenuModel,
        stage: String
    ) {
        let categories = ContainerMenuMovieBridge.categoryLabels(runtime: runtime)
        let rows = ContainerMenuMovieBridge.entryLabels(runtime: runtime)
        print(
            "[INFO] swf container-menu \(stage): side \(model.side.rawValue), "
                + "\(categories.count) movie categories, \(rows.count) movie rows, "
                + "engine has \(model.active.categories.count) and \(model.active.entries.count)"
        )
        print("[INFO]   movie rows: \(rows.prefix(12).joined(separator: ", "))")
        let movieIndex = ContainerMenuMovieBridge.selectedIndex(runtime: runtime)
        print(
            "[INFO]   selection: movie \(movieIndex.map(String.init) ?? "none")"
                + ", engine \(model.active.selectedIndex) "
                + "(\(model.selectedEntry?.name ?? "none"))"
        )
        let vendorField = ContainerMenuMovieBridge.vendorGoldText(runtime: runtime) ?? "absent"
        print(
            "[INFO]   gold: player \(model.playerGold), container \(model.containerGold), "
                + "vendor field \(vendorField)"
        )
        if let entry = model.selectedEntry, let price = model.price(for: entry) {
            print("[INFO]   \(model.transferLabel) \(entry.name): \(price) gold")
        }
    }

    private static func printDiagnostics(
        _ runtime: SWFMovieRuntime,
        mode: ContainerMenuModel.Mode,
        model: ContainerMenuModel
    ) {
        let diagnostics = ContainerMenuMovieBridge.diagnostics(runtime: runtime)
        print(
            "[INFO] swf container-menu diagnostics: "
                + "\(ContainerMenuMovieBridge.moviePath(for: mode)), "
                + "\(runtime.nodeCount) nodes, \(diagnostics.faults) faults, "
                + "\(runtime.tally.unimplementedTotal) unimplemented opcodes, "
                + "\(diagnostics.unhandledInvokes) unhandled of "
                + "\(runtime.invokeLog.total) invokes, "
                + "\(diagnostics.missingNames) distinct missing names"
        )
        print(
            "[INFO]   totals: player \(model.player.entries.count) rows, "
                + "container \(model.container.entries.count) rows"
        )
        for entry in runtime.tally.rankedMissing.prefix(20) {
            print("[INFO]   missing \(entry.name) \(entry.count)")
        }
        for entry in runtime.invokeLog.entries where !entry.isHandled {
            print("[INFO]   unhandled \(entry.direction.rawValue) \(entry.name)")
        }
    }
}
