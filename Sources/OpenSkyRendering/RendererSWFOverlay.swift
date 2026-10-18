// A second running movie drawn over the main SWF layer, for a menu built from two
// movies, such as the book pages and the book menu's button bar
// (docs/rendering/swf-layer.md#overlay-movie).

import Metal
import OpenSkyFormatsSWF

/// The overlay movie's GPU package and the runtime that drives it.
nonisolated public struct SWFOverlayLayer {
    public let movie: SWFMovieResources
    public let runtime: SWFMovieRuntime
}

extension Renderer {
    public var swfOverlayRuntime: SWFMovieRuntime? {
        swf.overlay?.runtime
    }

    /// Builds and starts `scene` as the overlay, or clears the overlay for nil. `prepare`
    /// runs before `start()`, as for the main movie.
    @discardableResult
    public func setSWFOverlay(
        _ scene: SWFMovieScene?, prepare: ((SWFMovieRuntime) -> Void)? = nil
    ) throws -> SWFMovieRuntime? {
        purgeRetiredResources()
        if let old = swf.overlay {
            swf.overlay = nil
            retireAllocations(old.movie.residencyAllocations)
            releaseSWFGlyphs(generation: old.movie.generation)
        }
        guard let scene else { return nil }
        swf.generation += 1
        let movie = try SWFMovieResources(device: device, scene: scene, generation: swf.generation)
        residencySet.addAllocations(movie.residencyAllocations)
        residencySet.commit()
        let runtime = SWFMovieRuntime(movieScene: scene, limits: .standard)
        runtime.textTranslator = swfTextTranslator
        prepare?(runtime)
        runtime.start()
        swf.overlay = SWFOverlayLayer(movie: movie, runtime: runtime)
        try updateSWFScene(runtime.makeScene(), of: movie)
        return runtime
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
