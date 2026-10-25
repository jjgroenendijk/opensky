// `render`: the offscreen world view of a grid cell.

import ArgumentParser

public struct RenderArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a world view of a grid cell offscreen and save it as a PNG.",
        discussion: "Use render for a cell as the game streams it, with effects and overlays. "
            + "Use preview for one record, reference, or mesh from fixed angles, and "
            + "'game screenshot' for the running app's window. --zoom moves the eye toward "
            + "the framed center. The effect options force image space, a modifier, a "
            + "membrane on the first actor, or a weather; --frames warms them up."
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(parsing: .unconditional, help: ArgumentHelp("The PNG to write.", valueName: "file"))
    public var out: String
    @Option(parsing: .unconditional, help: ArgumentHelp("The image size.", valueName: "WxH"))
    public var size = PixelSize.defaultView
    @Option(parsing: .unconditional, help: ArgumentHelp("0.1 to 10.", valueName: "factor"))
    public var zoom: Float = 1
    @Option(parsing: .unconditional, help: ArgumentHelp("An hour, 0 to 24.", valueName: "hour"))
    public var timeOfDay: Float = 13
    @Flag(help: "Add the 8 surrounding cells.")
    public var neighbors = false
    @Flag(help: "Overlay the screen-space UI sample and print its draw stats.")
    public var uiSample = false
    @Flag(help: "Draw the navmesh.")
    public var navmeshOverlay = false
    @Flag(help: "Draw perception cones and investigate lines for every actor.")
    public var detectionOverlay = false
    @OptionGroup public var effects: EffectCaptureArguments

    public init() {}

    public func validate() throws {
        try OptionCheck.range(zoom, 0.1 ... 10, "--zoom")
        try OptionCheck.range(timeOfDay, 0 ... 24, "--time-of-day")
    }
}

/// The effect A/B options of `render`.
public struct EffectCaptureArguments: ParsableArguments, Sendable {
    @Flag(help: "Skip the image-space composite pass.")
    public var imageSpaceOff = false
    @Flag(help: "Skip HDR tone mapping inside the image-space pass.")
    public var toneMappingOff = false
    @Option(parsing: .unconditional, help: ArgumentHelp("Force an IMGS.", valueName: "edid"))
    public var imgs: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Start an IMAD.", valueName: "edid"))
    public var imad: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("The time to sample the IMAD at.", valueName: "seconds")
    )
    public var imadAt: Float = 0
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Put an EFSH membrane on the first actor.", valueName: "edid")
    )
    public var membrane: String?
    @Flag(help: "Frame the first actor from about two meters away.")
    public var frameActor = false
    @Option(parsing: .unconditional, help: ArgumentHelp("Force a weather.", valueName: "edid"))
    public var weather: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Frames to run first, 1 to 600.", valueName: "n")
    )
    public var frames = 1
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "Turn surface shading terms off: comma-separated names, or all.",
            valueName: "terms"
        )
    )
    public var shadingOff: CommaList?

    public init() {}

    public func validate() throws {
        try OptionCheck.atLeast(imadAt, 0, "--imad-at")
        try OptionCheck.range(frames, 1 ... 600, "--frames")
    }
}
