// `render` options: the parsed command line and the camera and clock parsers.

import OpenSkyCells
import OpenSkyCLIArguments
import OpenSkyRendering

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

    static func parseOptions(_ arguments: RenderArguments) throws -> Options {
        try Options(
            worldspace: arguments.grid.worldspace
                ?? FirstRenderCell.worldspaceEditorID,
            gridX: arguments.grid.x ?? FirstRenderCell.gridX,
            gridY: arguments.grid.y ?? FirstRenderCell.gridY,
            output: arguments.out,
            size: (arguments.size.width, arguments.size.height),
            zoom: arguments.zoom,
            timeOfDay: arguments.timeOfDay == 24 ? 0 : arguments.timeOfDay,
            neighbors: arguments.neighbors,
            uiSample: arguments.uiSample,
            navmeshOverlay: arguments.navmeshOverlay,
            detectionOverlay: arguments.detectionOverlay,
            effects: EffectCaptureOptions.parse(arguments.effects)
        )
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
