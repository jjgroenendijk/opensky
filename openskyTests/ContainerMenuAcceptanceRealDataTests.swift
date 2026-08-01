// M12.2.3 container and barter menu acceptance against the user's read-only
// Skyrim SE install (issue #179). Both movies decode and statically render but
// had never been driven; this is the standing gate for their bring-up, their
// data contract, and a real buy and sell settled through the engine's own
// accounting. Rendered frames and numeric evidence stay in ignored logs/.

import Foundation
import Metal
import MetalKit
@testable import opensky
import Testing

struct ContainerMenuAcceptanceRealDataTests {
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
    func vanillaContainerMenuBringsUpCleanAndTransfers() throws {
        try drive(mode: .container)
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func vanillaBarterMenuBringsUpCleanBuysAndSells() throws {
        try drive(mode: .barter)
    }

    /// Bring-up, publication, one navigation step, then one transaction from
    /// each side, with a frame captured at every stage.
    @MainActor
    private func drive(mode: ContainerMenuModel.Mode) throws {
        let root = try #require(Self.dataRoot)
        let renderer = try makeRenderer(device: #require(Self.device))
        let empty = try render(renderer)

        let scene = try SWFMovieLoader(fileSystem: VirtualFileSystem(root: root))
            .load(path: ContainerMenuMovieBridge.moviePath(for: mode))
        #expect(
            scene.movie.importDiagnostics.unresolvedPlaceholders == 0,
            "an imported list clip did not resolve"
        )
        let runtime = try bringUp(scene, mode: mode, renderer: renderer)
        let broughtUp = try render(renderer)

        let shop = try makeShop(root: root, mode: mode)
        var model = shop.model
        #expect(!model.active.entries.isEmpty, "the probe container produced no rows")
        try publish(model, renderer: renderer)
        let published = try render(renderer)
        verifyPublished(model, mode: mode, runtime: runtime)

        #expect(try ContainerMenuMovieBridge.send(.move(.down), renderer: renderer))
        try model.select(#require(ContainerMenuMovieBridge.selectedIndex(runtime: runtime)))
        #expect(model.active.selectedIndex > 0, "the movie's list never moved")
        try publish(model, renderer: renderer)

        let outcome = try trade(shop: shop, model: &model, renderer: renderer)
        let traded = try render(renderer)

        let diagnostics = verifyClean(runtime: runtime, renderer: renderer)
        let broughtUpChanged = Self.changedPixels(empty.pixels, broughtUp.pixels)
        #expect(broughtUpChanged > 100, "bring-up changed only \(broughtUpChanged) pixels")
        let publishedChanged = Self.changedPixels(broughtUp.pixels, published.pixels)
        #expect(publishedChanged > 100, "publishing rows changed only \(publishedChanged) pixels")

        try ContainerMenuEvidence.write(
            mode: mode,
            frames: [
                ("empty", empty), ("brought-up", broughtUp),
                ("published", published), ("traded", traded)
            ],
            runtime: runtime,
            stats: renderer.lastSWFDrawStats,
            measurement: ContainerMenuEvidence.Measurement(
                diagnostics: diagnostics,
                nodes: runtime.nodeCount,
                importSummary: scene.movie.importDiagnostics.summary,
                rows: ContainerMenuMovieBridge.entryLabels(runtime: runtime),
                pricing: model.pricing,
                outcome: outcome,
                vendorGold: ContainerMenuMovieBridge.vendorGoldText(runtime: runtime),
                broughtUpChanged: broughtUpChanged,
                publishedChanged: publishedChanged
            )
        )
    }

    @MainActor
    private func bringUp(
        _ scene: SWFMovieScene,
        mode: ContainerMenuModel.Mode,
        renderer: Renderer
    ) throws -> SWFMovieRuntime {
        try renderer.setSWFMovie(scene)
        renderer.swfEnabled = true
        let runtime = try #require(
            try renderer.startSWFRuntime(prepare: ContainerMenuMovieBridge.prepare(runtime:))
        )
        try renderer.updateSWFRuntime { runtime in
            ContainerMenuMovieBridge.activate(runtime: runtime, mode: mode) { _ in }
        }
        for _ in 0 ..< GameViewController.containerMenuActivationTicks {
            try renderer.advanceSWFRuntime()
        }
        return runtime
    }

    /// The engine's rows are the movie's rows, and the merchant purse reached
    /// the movie's own vendor field. The purse field is placed by the player
    /// info card's `Barter` frame, so it exists in the barter movie and not in
    /// the container one.
    @MainActor
    private func verifyPublished(
        _ model: ContainerMenuModel,
        mode: ContainerMenuModel.Mode,
        runtime: SWFMovieRuntime
    ) {
        #expect(
            ContainerMenuMovieBridge.entryLabels(runtime: runtime)
                == model.active.entries.map(\.name),
            "the movie's rows are not the engine's"
        )
        let vendorGold = ContainerMenuMovieBridge.vendorGoldText(runtime: runtime)
        if mode == .barter {
            #expect(
                vendorGold == "\(model.containerGold)",
                "the merchant purse did not reach the movie"
            )
        } else {
            #expect(vendorGold == nil)
        }
    }

    /// The milestone's stated target: zero faults, zero unimplemented opcodes
    /// and zero unanswered engine calls.
    @MainActor
    private func verifyClean(
        runtime: SWFMovieRuntime,
        renderer: Renderer
    ) -> InventoryMenuDiagnostics {
        let diagnostics = ContainerMenuMovieBridge.diagnostics(runtime: runtime)
        #expect(diagnostics.faults == 0, "the movie faulted \(diagnostics.faults) times")
        #expect(runtime.tally.unimplementedTotal == 0)
        #expect(
            diagnostics.unhandledInvokes == 0,
            "the movie made \(diagnostics.unhandledInvokes) unanswered engine calls"
        )
        #expect(renderer.lastSWFDrawStats.drawCalls > 0, "the menu drew nothing")
        return diagnostics
    }

    /// One transaction from each side, asserting that gold and items are
    /// conserved across the pair. Container mode takes and stores instead.
    @MainActor
    private func trade(
        shop: ProbeShop,
        model: inout ContainerMenuModel,
        renderer: Renderer
    ) throws -> String {
        let before = shop.totals()
        let bought = try take(shop: shop, model: &model, renderer: renderer)
        model.switchSide()
        try publish(model, renderer: renderer)
        let sold = try take(shop: shop, model: &model, renderer: renderer)
        #expect(shop.totals() == before, "the pair of transactions was not conserving")
        return "\(bought), \(sold)"
    }

    @MainActor
    private func take(
        shop: ProbeShop,
        model: inout ContainerMenuModel,
        renderer: Renderer
    ) throws -> String {
        let entry = try #require(model.selectedEntry)
        let outcome: String
        switch (model.mode, model.side) {
        case (.barter, .container):
            outcome = try "bought \(entry.name) for \(shop.session.buy(entry.item).gold) gold"
        case (.barter, .player):
            outcome = try "sold \(entry.name) for \(shop.session.sell(entry.item).gold) gold"
        case (.container, .container):
            try shop.inventory.transfer(entry.item, count: 1, from: shop.container, to: .player)
            outcome = "took \(entry.name)"
        case (.container, .player):
            try shop.inventory.transfer(entry.item, count: 1, from: .player, to: shop.container)
            outcome = "stored \(entry.name)"
        }
        var rebuilt = shop.rebuild(mode: model.mode)
        rebuilt.restore(from: model)
        model = rebuilt
        try publish(model, renderer: renderer)
        return outcome
    }

    @MainActor
    private func publish(_ model: ContainerMenuModel, renderer: Renderer) throws {
        try renderer.updateSWFRuntime { runtime in
            ContainerMenuMovieBridge.publish(model, runtime: runtime)
        }
        try renderer.advanceSWFRuntime()
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

private enum ContainerMenuEvidence {
    struct Measurement {
        let diagnostics: InventoryMenuDiagnostics
        let nodes: Int
        let importSummary: String
        let rows: [String]
        let pricing: BarterPricing
        let outcome: String
        let vendorGold: String?
        let broughtUpChanged: Int
        let publishedChanged: Int
    }

    @MainActor
    static func write(
        mode: ContainerMenuModel.Mode,
        frames: [(String, (texture: MTLTexture, pixels: [UInt8]))],
        runtime: SWFMovieRuntime,
        stats: SWFDrawStats,
        measurement: Measurement
    ) throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        for (name, frame) in frames {
            try FrameScreenshot.write(
                texture: frame.texture,
                to: logs.appending(path: "\(mode.rawValue)-menu-\(name).png")
            )
        }
        let missing = runtime.tally.rankedMissing
            .prefix(12)
            .map { "\($0.name) \($0.count)" }
            .joined(separator: ", ")
        let report = """
        [INFO] movie: \(ContainerMenuMovieBridge.moviePath(for: mode))
        [INFO] import merge: \(measurement.importSummary)
        [INFO] display nodes: \(measurement.nodes)
        [INFO] faults: \(measurement.diagnostics.faults)
        [INFO] unimplemented opcodes: \(runtime.tally.unimplementedTotal)
        [INFO] draw calls: \(stats.drawCalls) · skipped items: \(stats.skippedItems)
        [INFO] bring-up changed pixels: \(measurement.broughtUpChanged)
        [INFO] published changed pixels: \(measurement.publishedChanged)
        [INFO] distinct missing names: \(measurement.diagnostics.missingNames) \
        (total hits \(runtime.tally.missingTotal))
        [INFO] top missing: \(missing)
        [INFO] pricing: \(measurement.pricing.source), factor \
        \(measurement.pricing.basePriceFactor)
        [INFO] movie vendor gold: \(measurement.vendorGold ?? "absent")
        [INFO] movie rows: \(measurement.rows.prefix(20).joined(separator: ", "))
        [INFO] transactions: \(measurement.outcome)
        [INFO] host functions: \(runtime.hostFunctionNames.sorted().joined(separator: ", "))
        [INFO] movie callbacks: \(runtime.movieCallbackNames.sorted().joined(separator: ", "))
        [INFO] unhandled invokes: \(runtime.invokeLog.unhandled) of \(runtime.invokeLog.total)
        """
        try report.write(
            to: logs.appending(path: "\(mode.rawValue)-menu-acceptance.log"),
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
