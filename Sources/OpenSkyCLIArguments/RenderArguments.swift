// The offscreen render command.

import ArgumentParser

public struct ScreenshotArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Save an offscreen world frame as a PNG.",
        discussion: "--zoom moves the eye toward the framed center. --neighbors adds the 8 "
            + "cells around it. The effect options force image space, a modifier, a "
            + "membrane on the first actor, or a weather; --frames warms them up. "
            + "--frame-actor frames the first actor without an effect.",
        aliases: ["render"]
    )
    @OptionGroup public var global: GlobalOptions
    @OptionGroup public var grid: GridOptions
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "file"))
    public var out: String
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "WxH"))
    public var size: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("From 0.1 to 10.", valueName: "f"))
    public var zoom: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("An hour from 0 to 24. Default: 13.", valueName: "hour")
    )
    public var timeOfDay: String?
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
}

/// The effect A/B options of `screenshot`.
public struct EffectCaptureArguments: ParsableArguments, Sendable {
    @Flag(help: "Skip the image-space composite pass.")
    public var imageSpaceOff = false
    @Flag(help: "Skip HDR tone mapping inside the image-space pass.")
    public var toneMappingOff = false
    @Option(parsing: .unconditional, help: ArgumentHelp("Force an IMGS.", valueName: "edid"))
    public var imgs: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Start an IMAD.", valueName: "edid"))
    public var imad: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "seconds"))
    public var imadAt: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Put an EFSH membrane on the first actor.", valueName: "edid")
    )
    public var membrane: String?
    @Flag(help: "Frame the first actor from about two meters away.")
    public var frameActor = false
    @Option(parsing: .unconditional, help: ArgumentHelp("Force a weather.", valueName: "edid"))
    public var weather: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("From 1 to 600.", valueName: "n"))
    public var frames: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp(
            "Turn surface shading terms off: comma-separated names, or all.",
            valueName: "terms"
        )
    )
    public var shadingOff: String?

    public init() {}
}
