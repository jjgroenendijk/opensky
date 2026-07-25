// The dynamic SWF path (M8.3.2): bringing a movie's ActionScript up, ticking
// it, and pushing the resulting draw-command stream into the already-built GPU
// package.
//
// `setSWFMovie` stays the heavy call — it tessellates every shape, uploads
// every bitmap, and bakes the gradient ramp. `updateSWFScene` is the cheap one:
// it re-plans draw ops, uniforms, and text runs from a new command stream and
// keeps every static GPU resource, which is what makes per-frame AS2 mutation
// affordable.
//
// The layer is driven by an explicit tick and nothing else. `advanceSWFRuntime`
// is the only thing that moves a playhead; a renderer that never calls it
// produces byte-identical frames forever, which is the determinism contract in
// docs/rendering/ui.md.

import Metal

extension Renderer {
    /// The AS2 runtime driving the assigned movie, or nil while the layer is on
    /// the static frame-1 path.
    var swfRuntime: SWFMovieRuntime? {
        swf.runtime
    }

    /// Brings the assigned movie's ActionScript up — every `DoInitAction`
    /// block, then frame 1, then that frame's `DoAction` — and pushes the
    /// display list it produced. Returns nil when no movie is assigned.
    @discardableResult
    func startSWFRuntime(limits: AS2Limits = .standard) throws -> SWFMovieRuntime? {
        guard let movie = swf.movie else {
            return nil
        }
        let runtime = SWFMovieRuntime(movieScene: movie.scene, limits: limits)
        runtime.start()
        swf.runtime = runtime
        try updateSWFScene(runtime.makeScene())
        return runtime
    }

    /// One explicit tick of the assigned movie. Pushes a new command stream
    /// only when the tick actually changed the display list, so an idle movie
    /// costs one dirty-flag read.
    func advanceSWFRuntime() throws {
        guard let runtime = swf.runtime else {
            return
        }
        runtime.advance()
        guard let scene = runtime.sceneIfChanged() else {
            return
        }
        try updateSWFScene(scene)
    }

    /// Drops the runtime and restores the movie's static frame-1 stream.
    func stopSWFRuntime() throws {
        guard swf.runtime != nil, let movie = swf.movie else {
            swf.runtime = nil
            return
        }
        swf.runtime = nil
        try updateSWFScene(SWFScene.build(movie: movie.scene.movie))
    }

    /// Replaces what the layer draws with a new command stream, retaining the
    /// movie's tessellation, textures, gradient ramp, and glyph atlas. Rings
    /// grow when the stream outgrows them; the old buffers retire once
    /// in-flight frames drain, exactly like a movie swap.
    ///
    /// Main thread, between frames — the same contract as `setSWFMovie`.
    func updateSWFScene(_ scene: SWFScene) throws {
        guard let movie = swf.movie else {
            return
        }
        purgeRetiredResources()
        let retiring = try movie.update(scene: scene, device: device)
        guard !retiring.isEmpty else {
            return
        }
        residencySet.addAllocations(movie.residencyAllocations)
        residencySet.commit()
        retireAllocations(retiring)
    }
}
