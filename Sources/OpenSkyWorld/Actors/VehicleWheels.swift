// Where a towed cart's wheels touch the ground, and how the cart rests on them.
// See docs/engine/vehicles.md.

import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import simd

nonisolated public enum VehicleWheels {
    /// The model-frame x and y of each wheel node. A wheel touches the ground below
    /// its centre.
    public static func contacts(in file: NIFFile) throws -> [SIMD2<Float>] {
        try nodes(in: file).map { SIMD2($0.transform.columns.3.x, $0.transform.columns.3.y) }
    }

    /// Each node named `Wheel...`, such as the prisoner carriage's `WheelBackLeft`,
    /// with its model-frame transform, in file order.
    static func nodes(in file: NIFFile) throws -> [(name: String, transform: float4x4)] {
        let hierarchy = try NIFNodeHierarchy(file: file)
        return hierarchy.names.sorted { $0.key < $1.key }.compactMap { index, name in
            guard
                name.lowercased().hasPrefix("wheel"),
                let transform = hierarchy.worldTransforms[index]
            else { return nil }
            return (name, transform)
        }
    }

    /// How a cart rests on the ground under its wheels.
    struct Rest: Equatable {
        /// The height of the cart's origin.
        let height: Float
        /// Turns the level cart's up axis onto the ground plane's normal.
        let tilt: float4x4
    }

    /// Fits a plane to the ground under the wheels, then lifts it until no wheel is
    /// below the ground. `orientation` is the level cart's rotation; nil with fewer
    /// than three wheels on ground, or wheels on one line.
    static func rest(
        on wheels: [SIMD2<Float>],
        at origin: SIMD2<Float>,
        orientation: float4x4,
        top: Float,
        ground: (SIMD3<Float>) -> Float?
    ) -> Rest? {
        var points: [SIMD3<Float>] = []
        for wheel in wheels {
            let offset = orientation * SIMD4(wheel.x, wheel.y, 0, 0)
            let spot = origin + SIMD2(offset.x, offset.y)
            if let height = ground(SIMD3(spot.x, spot.y, top)) {
                points.append(SIMD3(offset.x, offset.y, height))
            }
        }
        guard points.count >= 3, let plane = Plane(fitting: points) else { return nil }
        let lift = points.map { $0.z - plane.height(at: $0) }.max() ?? 0
        let normal = simd_normalize(SIMD3(-plane.slope.x, -plane.slope.y, 1))
        return Rest(
            height: plane.origin + lift,
            tilt: float4x4(simd_quatf(from: SIMD3(0, 0, 1), to: normal))
        )
    }

    /// `orientation` with its up axis turned straight up, keeping its heading.
    static func levelled(_ orientation: float3x3) -> float4x4 {
        let rotation = float4x4(
            SIMD4(orientation.columns.0, 0), SIMD4(orientation.columns.1, 0),
            SIMD4(orientation.columns.2, 0), SIMD4(0, 0, 0, 1)
        )
        let up = simd_normalize(orientation.columns.2)
        guard up.z > 0.01 else { return rotation }
        return float4x4(simd_quatf(from: up, to: SIMD3(0, 0, 1))) * rotation
    }

    /// The least-squares plane `z = origin + slope.x * x + slope.y * y`.
    private struct Plane {
        let origin: Float
        let slope: SIMD2<Float>

        init?(fitting points: [SIMD3<Float>]) {
            let count = Float(points.count)
            let mean = points.reduce(SIMD3<Float>.zero, +) / count
            var xx: Float = 0, xy: Float = 0, yy: Float = 0, xz: Float = 0, yz: Float = 0
            for point in points {
                let delta = point - mean
                xx += delta.x * delta.x
                xy += delta.x * delta.y
                yy += delta.y * delta.y
                xz += delta.x * delta.z
                yz += delta.y * delta.z
            }
            let determinant = xx * yy - xy * xy
            // Zero when the wheels are on one line, so the roll is unknown.
            guard determinant > 1e-6 * (xx + yy) * (xx + yy) else { return nil }
            slope = SIMD2((xz * yy - yz * xy) / determinant, (yz * xx - xz * xy) / determinant)
            origin = mean.z - slope.x * mean.x - slope.y * mean.y
        }

        func height(at point: SIMD3<Float>) -> Float {
            origin + slope.x * point.x + slope.y * point.y
        }
    }
}
