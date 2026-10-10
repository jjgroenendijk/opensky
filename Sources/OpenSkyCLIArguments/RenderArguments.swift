// The offscreen render, bench, and benchmark commands.

import ArgumentParser

public struct ScreenshotArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Save an offscreen world frame as a PNG.",
        discussion: "--zoom moves the eye toward the framed center. --neighbors adds the 8 "
            + "cells around it. The effect options force image space, a modifier, a "
            + "membrane on the first actor, or a weather; --frames warms them up.",
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
    @Option(parsing: .unconditional, help: ArgumentHelp("Force a weather.", valueName: "edid"))
    public var weather: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("From 1 to 600.", valueName: "n"))
    public var frames: String?

    public init() {}
}

public struct LaunchBenchArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "launch-bench",
        abstract: "Time each stage of the world data load the app runs before its window."
    )
    @OptionGroup public var global: GlobalOptions

    public init() {}
}

public struct BenchmarkArguments: CLICommandArguments {
    public static let configuration = CommandConfiguration(
        commandName: "benchmark",
        abstract: "The shared benchmark: cold and warm cell loads, then frame time.",
        discussion: "--out writes stable JSON and --frame a PNG of the measured view."
    )
    @OptionGroup public var global: GlobalOptions
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "file"))
    public var out: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "png"))
    public var frame: String?
    @Option(parsing: .unconditional, help: ArgumentHelp("Default: 2560x1600.", valueName: "WxH"))
    public var size: String?
    @Flag(help: "Time the process start and its first 60 s.")
    public var launch = false
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "s"))
    public var launchSeconds: String?
    @Flag(help: "Walk the shared route with live streaming.")
    public var route = false
    @Flag(help: "Delete the saved pipeline archive first.")
    public var coldPipelines = false
    @Flag(help: "Cull static groups on the CPU.")
    public var cpuCulling = false
    @Flag(help: "Stream texture levels.")
    public var textureStreaming = false
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "MiB"))
    public var textureBudget: String?
    @Option(
        parsing: .unconditional,
        help: ArgumentHelp("Render at 50 to 100 percent and upscale.", valueName: "percent")
    )
    public var renderScale: String?
    @Option(parsing: .unconditional, help: ArgumentHelp(valueName: "temporal|spatial"))
    public var upscaler: String?
    @Flag(help: "Build a MetalFX frame between real frames.")
    public var frameInterpolation = false
    @Flag(help: "Draw grass with object and mesh shaders.")
    public var meshShaderGrass = false
    @OptionGroup public var assets: AssetLoadArguments

    public init() {}
}
