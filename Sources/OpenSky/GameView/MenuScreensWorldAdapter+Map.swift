// Where the map camera sees a marker, for the map movie.

import Foundation
import OpenSkyCamera
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld

extension MenuScreensWorldAdapter: MapMovieWorld {
    func mapScreenPoint(_ point: SIMD3<Float>) -> SIMD2<Float>? {
        guard
            let pose = game.mapWorld.mapViewPose,
            let session = game.gameSession,
            let renderer = game.renderer
        else { return nil }
        let view = MenuScene(
            eye: pose.eye, target: pose.lookAt, up: SIMD3(0, 0, 1),
            fovYRadians: session.sessionFOVYRadians
        )
        guard let screen = view.screenPoint(point, aspectRatio: renderer.drawableAspectRatio),
              (0 ... 1).contains(screen.x), (0 ... 1).contains(screen.y)
        else { return nil }
        return screen
    }
}
