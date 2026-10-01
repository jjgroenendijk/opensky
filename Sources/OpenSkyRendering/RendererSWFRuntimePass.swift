// The dynamic SWF path: start a movie's ActionScript, tick it, and push the draw
// commands into the built package. `updateSWFScene` re-plans cheaply; `setSWFMovie` is
// the heavy build. Only `advanceSWFRuntime` moves a playhead, so frames are
// deterministic (docs/rendering/swf-layer.md).

import Metal
import OpenSkyFormatsSWF

extension Renderer {
    /// The AS2 runtime driving the assigned movie, or nil while the layer is on
    /// the static frame-1 path.
    public var swfRuntime: SWFMovieRuntime? {
        swf.runtime
    }

    /// Starts the movie's ActionScript (`DoInitAction`, frame 1, `DoAction`) and pushes its
    /// display list. Nil without a movie. `prepare` runs before `start()`, because bring-up
    /// already calls the host (`startmenu.swf` logs 24 times).
    @discardableResult
    public func startSWFRuntime(
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
    public func advanceSWFRuntime() throws {
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
    public func sendSWFInput(_ event: SWFInputEvent) throws -> Bool {
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
    public func callSWFMovie(_ name: String, arguments: [AS2Value] = []) throws -> AS2Value {
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
    public func callSWFMovie(
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
    public func updateSWFRuntime(_ body: (SWFMovieRuntime) -> Void) throws {
        guard let runtime = swf.runtime else {
            return
        }
        body(runtime)
        try synchronizeSWFRuntime(runtime)
    }

    /// Drops the runtime and restores the movie's static frame-1 stream.
    public func stopSWFRuntime() throws {
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
    public func updateSWFScene(_ scene: SWFScene) throws {
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
