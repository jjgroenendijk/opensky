// M12.2.2 inventory menu acceptance against the user's read-only Skyrim SE
// install (issue #289). `inventorymenu.swf` is the third-largest AS2 consumer
// and had never been driven; it also places three characters it does not
// define, so it needs cross-movie import resolution before it has a list at
// all. This test is the standing gate for its bring-up, its data contract and
// its navigation. Rendered frames and numeric evidence stay in ignored logs/.

import Foundation
import Metal
import MetalKit
@testable import opensky
import Testing

struct InventoryMenuAcceptanceRealDataTests {
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    private static let width = 1280
    private static let height = 720

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func vanillaInventoryMenuBringsUpCleanPublishesItemsAndNavigates() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        let fileSystem = VirtualFileSystem(root: root)
        let renderer = try makeRenderer(device: device)

        let empty = try render(renderer)

        let movie = try SWFMovieLoader(fileSystem: fileSystem).load(
            path: InventoryMenuMovieBridge.moviePath
        )
        // The three list clips are imported, not defined. Without the merge the
        // menu comes up as eleven nodes and no list, which is what this asserts.
        #expect(
            movie.movie.importDiagnostics.unresolvedPlaceholders == 0,
            "an imported list clip did not resolve"
        )
        try renderer.setSWFMovie(movie)
        renderer.swfEnabled = true
        let runtime = try #require(
            try renderer.startSWFRuntime(prepare: InventoryMenuMovieBridge.prepare(runtime:))
        )
        try renderer.updateSWFRuntime { runtime in
            InventoryMenuMovieBridge.activate(runtime: runtime) { _ in }
        }
        for _ in 0 ..< GameViewController.inventoryMenuActivationTicks {
            try renderer.advanceSWFRuntime()
        }
        let broughtUp = try render(renderer)

        var model = try makeModel(root: root)
        #expect(!model.entries.isEmpty, "the probe inventory produced no rows")
        try renderer.updateSWFRuntime { runtime in
            InventoryMenuMovieBridge.publish(model, runtime: runtime)
        }
        try renderer.advanceSWFRuntime()
        let published = try render(renderer)

        let rows = InventoryMenuMovieBridge.entryLabels(runtime: runtime)
        let categories = InventoryMenuMovieBridge.categoryLabels(runtime: runtime)
        verifyPublished(rows: rows, categories: categories, model: model, runtime: runtime)
        let navigated = try navigate(renderer: renderer, runtime: runtime, model: &model)

        let diagnostics = verifyClean(runtime: runtime, renderer: renderer)
        let broughtUpChanged = Self.changedPixels(empty.pixels, broughtUp.pixels)
        #expect(broughtUpChanged > 100, "bring-up changed only \(broughtUpChanged) pixels")
        let publishedChanged = Self.changedPixels(broughtUp.pixels, published.pixels)
        #expect(publishedChanged > 100, "publishing rows changed only \(publishedChanged) pixels")

        try InventoryMenuEvidence.writeFrames(
            empty: empty, broughtUp: broughtUp, published: published, navigated: navigated.frame
        )
        try InventoryMenuEvidence.write(
            runtime: runtime,
            stats: renderer.lastSWFDrawStats,
            measurement: InventoryMenuEvidence.Measurement(
                diagnostics: diagnostics,
                categories: categories,
                rows: rows,
                selectedRow: navigated.selectedName,
                selectedCategory: navigated.selectedCategory,
                nodes: runtime.nodeCount,
                importSummary: movie.movie.importDiagnostics.summary,
                broughtUpChanged: broughtUpChanged,
                publishedChanged: publishedChanged,
                navigatedChanged: navigated.changed
            )
        )
    }

    /// The engine's rows are the movie's rows. Comparing the two read back off
    /// `EntriesA` is what proves the data contract crossed the bridge rather
    /// than that the engine still holds its own list.
    private func verifyPublished(
        rows: [String],
        categories: [String],
        model: InventoryMenuModel,
        runtime: SWFMovieRuntime
    ) {
        #expect(rows == model.entries.map(\.name), "the movie's rows are not the engine's")
        #expect(categories == model.categoryLabels)
        #expect(InventoryMenuMovieBridge.selectedIndex(runtime: runtime) == 0)
    }

    /// The milestone's stated target: zero faults, zero unimplemented opcodes
    /// and zero unanswered engine calls, matching `startmenu.swf`'s 0-of-36.
    @MainActor
    private func verifyClean(
        runtime: SWFMovieRuntime,
        renderer: Renderer
    ) -> InventoryMenuDiagnostics {
        let diagnostics = InventoryMenuMovieBridge.diagnostics(runtime: runtime)
        #expect(diagnostics.faults == 0, "inventorymenu.swf faulted \(diagnostics.faults) times")
        #expect(runtime.tally.unimplementedTotal == 0)
        #expect(
            diagnostics.unhandledInvokes == 0,
            "the movie made \(diagnostics.unhandledInvokes) unanswered engine calls"
        )
        #expect(renderer.lastSWFDrawStats.drawCalls > 0, "the menu drew nothing")
        return diagnostics
    }

    private struct NavigationMeasurement {
        let frame: (texture: MTLTexture, pixels: [UInt8])
        let selectedName: String
        let selectedCategory: String
        let changed: Int
    }

    /// Two category steps and three row steps. Category changes are
    /// engine-driven and republished; row moves go through the movie's own CLIK
    /// focus path, and the movie's answer is what the engine adopts.
    @MainActor
    private func navigate(
        renderer: Renderer,
        runtime: SWFMovieRuntime,
        model: inout InventoryMenuModel
    ) throws -> NavigationMeasurement {
        let before = try render(renderer)
        model.moveCategory(by: 2)
        try renderer.updateSWFRuntime { runtime in
            InventoryMenuMovieBridge.publish(model, runtime: runtime)
        }
        #expect(
            InventoryMenuMovieBridge.categoryLabels(runtime: runtime).count
                == model.categories.count
        )
        #expect(InventoryMenuMovieBridge.selectedCategoryIndex(runtime: runtime) == 2)
        #expect(
            InventoryMenuMovieBridge.entryLabels(runtime: runtime) == model.entries.map(\.name),
            "the filtered category did not reach the movie"
        )

        for _ in 0 ..< 2 {
            #expect(try InventoryMenuMovieBridge.send(.move(.down), renderer: renderer))
            let index = try #require(InventoryMenuMovieBridge.selectedIndex(runtime: runtime))
            model.select(index)
            try renderer.updateSWFRuntime { runtime in
                InventoryMenuMovieBridge.publish(model, runtime: runtime)
            }
        }
        #expect(model.selectedIndex > 0, "the movie's list never moved")
        let frame = try render(renderer)
        return NavigationMeasurement(
            frame: frame,
            selectedName: model.selectedEntry?.name ?? "none",
            selectedCategory: model.categoryLabels[model.selectedCategoryIndex],
            changed: Self.changedPixels(before.pixels, frame.pixels)
        )
    }

    /// A player inventory built from the install's own item index — two of each
    /// of the first few carryable forms per family, plus gold. Nothing is
    /// written to the install; the inventory lives in an in-memory store.
    @MainActor
    private func makeModel(root: GameDataRoot) throws -> InventoryMenuModel {
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let baselines = InventoryBaselineResolver.build(from: file)
        let inventory = InventoryRuntime(store: WorldStateStore(), baselines: baselines)
        for family in ItemDefinition.Family.allCases {
            for definition in baselines.items.definitions(of: family).prefix(3) {
                _ = try? inventory.add(definition.formID, count: 2, to: .player)
            }
        }
        try inventory.add(InventoryRuntime.vanillaGoldFormID, count: 137, to: .player)
        return InventoryMenuModel.build(holder: .player, runtime: inventory)
    }

    /// The engine-side row list must work with no install and no movie at all,
    /// so the milestone surface never depends on the movie coming up.
    @Test @MainActor
    func rowListIsIndependentOfTheMovie() throws {
        let baselines = try InventoryBaselineFixture.resolver()
        let inventory = InventoryRuntime(store: WorldStateStore(), baselines: baselines)
        try inventory.add(InventoryBaselineFixture.sword, count: 1, to: .player)
        var model = InventoryMenuModel.build(holder: .player, runtime: inventory)
        model.moveSelection(by: 1)
        #expect(model.selectedEntry?.name == "IronSword")
    }

    @MainActor
    private func makeRenderer(device: MTLDevice) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    @MainActor
    private func render(_ renderer: Renderer) throws -> (texture: MTLTexture, pixels: [UInt8]) {
        let texture = try renderer.renderOffscreen(
            width: Self.width, height: Self.height, animationTime: 1
        )
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: Self.width * 4,
                from: MTLRegionMake2D(0, 0, Self.width, Self.height),
                mipmapLevel: 0
            )
        }
        return (texture, pixels)
    }

    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).reduce(0) { count, index in
            let changed = (0 ..< 3).contains { lhs[index + $0] != rhs[index + $0] }
            return count + (changed ? 1 : 0)
        }
    }
}

private enum InventoryMenuEvidence {
    /// What the run measured, so the evidence writer stays inside the
    /// parameter-count limit.
    struct Measurement {
        let diagnostics: InventoryMenuDiagnostics
        let categories: [String]
        let rows: [String]
        let selectedRow: String
        let selectedCategory: String
        let nodes: Int
        let importSummary: String
        let broughtUpChanged: Int
        let publishedChanged: Int
        let navigatedChanged: Int
    }

    @MainActor
    static func writeFrames(
        empty: (texture: MTLTexture, pixels: [UInt8]),
        broughtUp: (texture: MTLTexture, pixels: [UInt8]),
        published: (texture: MTLTexture, pixels: [UInt8]),
        navigated: (texture: MTLTexture, pixels: [UInt8])
    ) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (frame, name) in [
            (empty, "inventory-menu-empty.png"),
            (broughtUp, "inventory-menu-brought-up.png"),
            (published, "inventory-menu-published.png"),
            (navigated, "inventory-menu-navigated.png")
        ] {
            try FrameScreenshot.write(texture: frame.texture, to: logs.appending(path: name))
        }
    }

    static func write(
        runtime: SWFMovieRuntime,
        stats: SWFDrawStats,
        measurement: Measurement
    ) throws {
        let missing = runtime.tally.rankedMissing
            .prefix(12)
            .map { "\($0.name) \($0.count)" }
            .joined(separator: ", ")
        let report = """
        [INFO] movie: \(InventoryMenuMovieBridge.moviePath)
        [INFO] import merge: \(measurement.importSummary)
        [INFO] display nodes: \(measurement.nodes)
        [INFO] faults: \(measurement.diagnostics.faults)
        [INFO] unimplemented opcodes: \(runtime.tally.unimplementedTotal)
        [INFO] actions executed: \(runtime.tally.actionsExecuted)
        [INFO] draw calls: \(stats.drawCalls) · skipped items: \(stats.skippedItems)
        [INFO] bring-up changed pixels: \(measurement.broughtUpChanged)
        [INFO] published changed pixels: \(measurement.publishedChanged)
        [INFO] navigated changed pixels: \(measurement.navigatedChanged)
        [INFO] distinct missing names: \(measurement.diagnostics.missingNames) \
        (total hits \(runtime.tally.missingTotal))
        [INFO] top missing: \(missing)
        [INFO] movie categories: \(measurement.categories.joined(separator: ", "))
        [INFO] movie rows: \(measurement.rows.prefix(20).joined(separator: ", "))
        [INFO] selection: \(measurement.selectedCategory) / \(measurement.selectedRow)
        [INFO] host functions: \(runtime.hostFunctionNames.sorted().joined(separator: ", "))
        [INFO] movie callbacks: \(runtime.movieCallbackNames.sorted().joined(separator: ", "))
        [INFO] unhandled invokes: \(runtime.invokeLog.unhandled) of \(runtime.invokeLog.total)
        """
        try report.write(
            to: logs.appending(path: "inventory-menu-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(report)
    }

    private static var logs: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "logs")
    }
}
