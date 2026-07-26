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
    ///
    /// `prepare` runs on the fresh runtime *before* `start()`. Bring-up is the
    /// first thing that calls out to the host — `startmenu.swf` makes 24
    /// `myLog` calls inside its own `DoInitAction` blocks — so a host surface
    /// installed after this returns arrives too late to answer them.
    @discardableResult
    func startSWFRuntime(
        limits: AS2Limits = .standard,
        prepare: ((SWFMovieRuntime) -> Void)? = nil
    ) throws -> SWFMovieRuntime? {
        guard let movie = swf.movie else {
            return nil
        }
        let runtime = SWFMovieRuntime(movieScene: movie.scene, limits: limits)
        prepare?(runtime)
        runtime.start()
        do {
            try updateSWFScene(runtime.makeScene())
            swf.runtime = runtime
        } catch {
            swf.runtime = nil
            throw error
        }
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

    /// Delivers one input event to the running movie and pushes whatever the
    /// movie changed in response. Returns true when the movie consumed the
    /// event, so the caller can give an unconsumed key to the world instead.
    /// Nothing here reads a clock or an event queue — the event is injected, on
    /// the main thread, between frames.
    @discardableResult
    func sendSWFInput(_ event: SWFInputEvent) throws -> Bool {
        guard let runtime = swf.runtime else {
            return false
        }
        let handled = runtime.handle(event)
        if let scene = runtime.sceneIfChanged() {
            try updateSWFScene(scene)
        }
        return handled
    }

    /// Calls a named callback the movie registered with `gfx.io.GameDelegate`,
    /// or a function on its root clip — the engine-to-movie half of the bridge —
    /// and pushes whatever the call changed.
    @discardableResult
    func callSWFMovie(_ name: String, arguments: [AS2Value] = []) throws -> AS2Value {
        guard let runtime = swf.runtime else {
            return .undefined
        }
        let result = runtime.callMovie(name, arguments: arguments)
        if let scene = runtime.sceneIfChanged() {
            try updateSWFScene(scene)
        }
        return result
    }

    /// Calls a function on a specific display-list instance, then pushes the
    /// changed command stream. Vanilla `hudmenu.swf` keeps its entry points on
    /// `/HUDMovieBaseInstance` instead of registering GameDelegate callbacks.
    @discardableResult
    func callSWFMovie(
        _ name: String,
        atPath path: String,
        arguments: [AS2Value] = []
    ) throws -> AS2Value {
        guard let runtime = swf.runtime else {
            return .undefined
        }
        let result = runtime.callMovie(name, atPath: path, arguments: arguments)
        try synchronizeSWFRuntime(runtime)
        return result
    }

    /// Applies one engine-owned mutation to the live runtime and synchronizes
    /// the renderer once. HUD initialization uses this to batch meter, compass,
    /// and prompt state without rebuilding the command stream after each call.
    func updateSWFRuntime(_ body: (SWFMovieRuntime) -> Void) throws {
        guard let runtime = swf.runtime else {
            return
        }
        body(runtime)
        try synchronizeSWFRuntime(runtime)
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

    private func synchronizeSWFRuntime(_ runtime: SWFMovieRuntime) throws {
        guard let scene = runtime.sceneIfChanged() else {
            return
        }
        do {
            try updateSWFScene(scene)
        } catch {
            runtime.markDirty()
            throw error
        }
    }
}
