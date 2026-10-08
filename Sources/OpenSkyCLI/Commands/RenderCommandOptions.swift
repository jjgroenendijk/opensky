// `render` options: the parsed command line and the camera and clock parsers.

import OpenSkyCLIArguments
import OpenSkyRendering
import OpenSkyWorld

extension RenderCommand {
    /// Everything `render` takes off the command line, parsed once. A value
    /// rather than a dozen locals because the command body has a strict length
    /// cap and every new overlay flag would otherwise eat into it.
    struct Options {
        let worldspace: String
        let gridX: Int32
        let gridY: Int32
        let output: String
        let size: (width: Int, height: Int)
        let zoom: Float
        let timeOfDay: Float
        let neighbors: Bool
        let uiSample: Bool
        let navmeshOverlay: Bool
        let detectionOverlay: Bool
        let effects: EffectCaptureOptions
    }

    static func parseOptions(_ arguments: ScreenshotArguments) throws -> Options {
        try Options(
            worldspace: arguments.grid.worldspace
                ?? FirstRenderCell.worldspaceEditorID,
            gridX: int32(arguments.grid.x, name: "--x") ?? FirstRenderCell.gridX,
            gridY: int32(arguments.grid.y, name: "--y") ?? FirstRenderCell.gridY,
            output: arguments.out,
            size: parseSize(arguments.size),
            zoom: parseZoom(arguments.zoom),
            timeOfDay: parseTimeOfDay(arguments.timeOfDay),
            neighbors: arguments.neighbors,
            uiSample: arguments.uiSample,
            navmeshOverlay: arguments.navmeshOverlay,
            detectionOverlay: arguments.detectionOverlay,
            effects: EffectCaptureOptions.parse(arguments.effects)
        )
    }

    /// The whole-cell framing camera is conservative (enclosing sphere +
    /// margin) -> sparse cells render small. `--zoom` moves the eye toward
    /// the target by that factor for a filled milestone shot; bounded so the
    /// eye cannot land on the target or behind the near plane content.
    static func parseZoom(_ value: String?) throws -> Float {
        guard let value else { return 1 }
        guard let zoom = Float(value), (0.1 ... 10).contains(zoom) else {
            throw CLIError.usage("--zoom expects a number in 0.1-10, got \(value)")
        }
        return zoom
    }

    static func parseTimeOfDay(_ value: String?) throws -> Float {
        guard let value else { return 13 }
        guard let hour = Float(value), (0 ... 24).contains(hour) else {
            throw CLIError.usage("--time-of-day expects an hour in 0-24, got \(value)")
        }
        return hour == 24 ? 0 : hour
    }

    static func zoomed(_ camera: SceneCamera, zoom: Float) -> SceneCamera {
        guard zoom != 1 else { return camera }
        return SceneCamera(
            eye: camera.target + (camera.eye - camera.target) / zoom,
            target: camera.target,
            sunDirection: camera.sunDirection,
            sunColor: camera.sunColor,
            ambientColor: camera.ambientColor
        )
    }
}
