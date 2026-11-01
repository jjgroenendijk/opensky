// The camera that world billboards turn to.

import OpenSkyFormatsMesh
import OpenSkyRendering
import simd

nonisolated extension NIFBillboard.Viewer {
    public init(camera: FreeFlyCamera) {
        self.init(
            eye: camera.position, forward: camera.forward,
            up: simd_normalize(simd_cross(camera.right, camera.forward))
        )
    }
}
