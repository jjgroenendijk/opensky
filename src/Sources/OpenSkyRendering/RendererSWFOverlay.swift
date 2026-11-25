// The SWF layers beside the main one: the HUD under it, and a second running movie
// over it, for a menu built from two movies, such as the book pages and the book
// menu's button bar
// (docs/rendering/swf-layer.md#overlay-movie).

import Metal
public import OpenSkyFormatsSWF

/// The overlay movie's GPU package and the runtime that drives it.
nonisolated public struct SWFOverlayLayer {
    public let movie: SWFMovieResources
    public let runtime: SWFMovieRuntime
}

extension Renderer {
    /// Builds and starts `scene` as the overlay, or clears the overlay for nil. `prepare`
    /// runs before `start()`, as for the main movie.
    @discardableResult
    public func setSWFOverlay(
        _ scene: SWFMovieScene?, prepare: ((SWFMovieRuntime) -> Void)? = nil
    ) throws -> SWFMovieRuntime? {
        retireSWFLayer(swf.overlay)
        swf.overlay = nil
        swf.overlay = try scene.map { try makeSWFLayer($0, prepare: prepare) }
        return swf.overlay?.runtime
    }

    /// The HUD movie on its own layer under the menus, or none for nil.
    @discardableResult
    public func setSWFHUD(
        _ scene: SWFMovieScene?, prepare: ((SWFMovieRuntime) -> Void)? = nil
    ) throws -> SWFMovieRuntime? {
        retireSWFLayer(swf.hud)
        swf.hud = nil
        swf.hud = try scene.map { try makeSWFLayer($0, prepare: prepare) }
        return swf.hud?.runtime
    }

    /// Applies one engine change to the HUD movie and pushes what it changed.
    public func updateSWFHUD(_ body: (SWFMovieRuntime) -> Void) throws {
        guard let hud = swf.hud else { return }
        body(hud.runtime)
        if let scene = hud.runtime.sceneIfChanged() {
            try updateSWFScene(scene, of: hud.movie)
        }
    }

    private func retireSWFLayer(_ layer: SWFOverlayLayer?) {
        purgeRetiredResources()
        guard let layer else { return }
        retireAllocations(layer.movie.residencyAllocations)
        releaseSWFGlyphs(generation: layer.movie.generation)
    }

    /// Builds the GPU package and starts the movie. `prepare` runs before `start()`,
    /// as for the main movie.
    private func makeSWFLayer(
        _ scene: SWFMovieScene, prepare: ((SWFMovieRuntime) -> Void)?
    ) throws -> SWFOverlayLayer {
        swf.generation += 1
        let movie = try SWFMovieResources(device: device, scene: scene, generation: swf.generation)
        residencySet.addAllocations(movie.residencyAllocations)
        residencySet.commit()
        let runtime = SWFMovieRuntime(movieScene: scene, limits: .standard)
        runtime.textTranslator = swfTextTranslator
        runtime.setGamepadCount(swf.gamepadCount)
        prepare?(runtime)
        runtime.start()
        try updateSWFScene(runtime.makeScene(), of: movie)
        return SWFOverlayLayer(movie: movie, runtime: runtime)
    }

    /// One tick of the overlay movie.
    public func advanceSWFOverlay() throws {
        guard let overlay = swf.overlay else { return }
        overlay.runtime.advance()
        if let scene = overlay.runtime.sceneIfChanged() {
            try updateSWFScene(scene, of: overlay.movie)
        }
    }

    /// Applies one engine change to the overlay movie and pushes what it changed.
    public func updateSWFOverlay(_ body: (SWFMovieRuntime) -> Void) throws {
        guard let overlay = swf.overlay else { return }
        body(overlay.runtime)
        if let scene = overlay.runtime.sceneIfChanged() {
            try updateSWFScene(scene, of: overlay.movie)
        }
    }
}
