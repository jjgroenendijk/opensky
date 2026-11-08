// A menu movie takes the whole SWF layer at full scale.

public import OpenSkyFormatsSWF

extension Renderer {
    /// Shows a menu movie at full scale and starts its runtime. False when no runtime started.
    public func startMenuMovie(
        _ scene: SWFMovieScene, prepare: ((SWFMovieRuntime) -> Void)? = nil
    ) throws -> Bool {
        try setSWFMovie(scene)
        swfEnabled = true
        swfScale = 1
        return try startSWFRuntime(prepare: prepare) != nil
    }
}
