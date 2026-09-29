// Shared synthetic-shape helper for capsule response tests.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
import simd

extension CapsuleCollisionTests {
    static func shape(
        geometry: NIFCollisionGeometry,
        center: SIMD3<Float>,
        localBounds: ModelBounds
    ) -> StaticCollisionShape {
        let transform = MatrixMath.translation(center)
        return StaticCollisionShape(
            reference: FormID(3),
            transform: transform,
            geometry: geometry,
            bounds: localBounds.transformed(by: transform)
        )
    }
}
