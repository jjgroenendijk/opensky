// Developer > UI Lab SWF section: shows one install movie on the SWF layer
// and drives its AS2 runtime one explicit tick at a time.
//
// Every entry point is a control action, so none throws. A decode, GPU, or
// runtime failure lands in `loadError` and shows in the readout.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

public final class SWFLabCoordinator {
    public private(set) var selectedPath: String?
    public private(set) var loadError: String?
    public private(set) var tally: SWFMovieTally?
    public private(set) var unresolvedFontNames: [String] = []

    private let movies: SWFMovieSource
    private let hud: HUDCoordinator
    private weak var world: SWFLayerWorld?

    public init(movies: SWFMovieSource, hud: HUDCoordinator) {
        self.movies = movies
        self.hud = hud
    }

    public func attach(world: SWFLayerWorld) {
        self.world = world
    }

    private var renderer: Renderer? {
        world?.renderer
    }

    public var moviePaths: [String] {
        movies.moviePaths
    }

    /// Reads the renderer's default, on, while there is no renderer.
    public var layerEnabled: Bool {
        get { renderer?.swfEnabled ?? true }
        set { renderer?.swfEnabled = newValue }
    }

    /// The lab owns the SWF layer while a movie is selected, so the HUD stops.
    /// Clearing the selection starts a fresh HUD.
    public func select(path: String?) {
        hud.suspend()
        renderer?.swfScale = 1
        selectedPath = path
        loadError = nil
        tally = nil
        unresolvedFontNames = []
        guard let path else {
            if renderer != nil {
                hud.start()
            }
            return
        }
        renderer?.swfEnabled = true
        guard movies.isAvailable else {
            loadError = "No game data located."
            assign(nil)
            return
        }
        movies.request(path, while: { [weak self] in
            self?.selectedPath == path
        }, then: { [weak self] result in
            self?.show(result)
        })
    }

    /// Runs when the movie is decoded, which may be a later frame than the selection.
    private func show(_ result: Result<SWFMovieScene, AssetLoadFailure>) {
        do {
            let scene = try result.get()
            tally = scene.movie.tally
            unresolvedFontNames = scene.unresolvedFontNames
            assign(scene)
        } catch {
            // The previous movie is cleared so the frame matches the readout.
            loadError = String(describing: error)
            assign(nil)
        }
    }

    public var snapshot: SWFLabControlSnapshot {
        SWFLabControlSnapshot(
            selectedPath: selectedPath,
            layerEnabled: layerEnabled,
            loadError: loadError,
            tally: tally,
            unresolvedFontNames: unresolvedFontNames,
            drawStats: renderer?.lastSWFDrawStats ?? SWFDrawStats(),
            installLoaded: movies.isAvailable,
            runtime: renderer?.swfRuntime.map(SWFLabRuntimeSnapshot.init(runtime:))
        )
    }

    private func assign(_ scene: SWFMovieScene?) {
        do {
            try renderer?.setSWFMovie(scene)
        } catch {
            loadError = "GPU package build failed: \(String(describing: error))"
        }
    }

    // MARK: - Runtime

    public func startRuntime() {
        guard let renderer else {
            loadError = Self.noRendererMessage
            return
        }
        do {
            guard try renderer.startSWFRuntime() != nil else {
                loadError = "Select a movie before starting the runtime."
                return
            }
            loadError = nil
        } catch {
            loadError = Self.runtimeMessage("start", error)
        }
    }

    /// Ticks one at a time, so a fault on tick 3 keeps the first two.
    public func advanceRuntime(ticks: Int) {
        guard let renderer = startedRenderer() else { return }
        do {
            for _ in 0 ..< max(1, ticks) {
                try renderer.advanceSWFRuntime()
            }
        } catch {
            loadError = Self.runtimeMessage("advance", error)
        }
    }

    public func stopRuntime() {
        guard let renderer else {
            loadError = Self.noRendererMessage
            return
        }
        do {
            try renderer.stopSWFRuntime()
            loadError = nil
        } catch {
            loadError = Self.runtimeMessage("stop", error)
        }
    }

    public func sendRuntimeInput(_ event: SWFInputEvent) {
        guard let renderer = startedRenderer() else { return }
        do {
            try renderer.sendSWFInput(event)
        } catch {
            loadError = Self.runtimeMessage("input", error)
        }
    }

    public func callRuntimeMovie(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            loadError = "Enter a callback name to call."
            return
        }
        guard let renderer = startedRenderer() else { return }
        do {
            try renderer.callSWFMovie(trimmed)
        } catch {
            loadError = Self.runtimeMessage("call", error)
        }
    }

    public func clearInvokeLog() {
        renderer?.swfRuntime?.clearInvokeLog()
    }

    /// A button press without a running movie says why it did nothing.
    private func startedRenderer() -> Renderer? {
        guard let renderer else {
            loadError = Self.noRendererMessage
            return nil
        }
        guard renderer.swfRuntime != nil else {
            loadError = "Runtime not started."
            return nil
        }
        return renderer
    }

    static let noRendererMessage = "No renderer: Metal 4 device unavailable."

    private static func runtimeMessage(_ stage: String, _ error: Error) -> String {
        "SWF runtime \(stage) failed: \(String(describing: error))"
    }
}

/// Lets the app's provider object stand in for its `SWFLabCoordinator`.
public protocol SWFLabControlForwarding: SWFLabControlProviding {
    var swfLab: SWFLabCoordinator { get }
}

extension SWFLabControlForwarding {
    public var swfMoviePaths: [String] {
        swfLab.moviePaths
    }

    public var swfLayerEnabled: Bool {
        get { swfLab.layerEnabled }
        set { swfLab.layerEnabled = newValue }
    }

    public var swfLabSnapshot: SWFLabControlSnapshot {
        swfLab.snapshot
    }

    public func selectSWFMovie(path: String?) {
        swfLab.select(path: path)
    }

    public func startSWFRuntime() {
        swfLab.startRuntime()
    }

    public func advanceSWFRuntime(ticks: Int) {
        swfLab.advanceRuntime(ticks: ticks)
    }

    public func stopSWFRuntime() {
        swfLab.stopRuntime()
    }

    public func sendSWFRuntimeInput(_ event: SWFInputEvent) {
        swfLab.sendRuntimeInput(event)
    }

    public func callSWFRuntimeMovie(_ name: String) {
        swfLab.callRuntimeMovie(name)
    }

    public func clearSWFInvokeLog() {
        swfLab.clearInvokeLog()
    }
}
