// Camera blocks for `NIFCameraTrack` tests: an `NiCamera`, its
// `NiTransformController`, `NiTransformInterpolator`, and `NiTransformData`.
// Layouts follow nif.xml; see docs/formats/nif.md#camera-animation.

import FormatsCoreTesting
import Foundation
import simd

extension NIFFixture {
    /// NiCamera after the AV-object prefix: flags, frustum, ortho, viewport,
    /// LOD adjust, scene ref, and two unknown uints.
    public static func niCamera(
        prefix: Data,
        frustumLeft: Float = -0.5,
        frustumRight: Float = 0.5,
        near: Float = 0.5
    ) -> Data {
        var out = prefix
        out.appendUInt16(0)
        for value in [frustumLeft, frustumRight, 0.3, -0.3, near, 1000] {
            out.appendFloat32(value)
        }
        out.append(0) // orthographic
        for value: Float in [0, 1, 1, 0, 1] {
            out.appendFloat32(value)
        }
        out.appendUInt32(UInt32(bitPattern: -1))
        out.appendUInt32(0)
        out.appendUInt32(0)
        return out
    }

    public static func transformController(interpolator: Int32, start: Float, stop: Float) -> Data {
        var out = Data()
        out.appendUInt32(UInt32(bitPattern: -1)) // next controller
        out.appendUInt16(0x0C)
        out.appendFloat32(1)
        out.appendFloat32(0)
        out.appendFloat32(start)
        out.appendFloat32(stop)
        out.appendUInt32(0) // target
        out.appendUInt32(UInt32(bitPattern: interpolator))
        return out
    }

    public static func transformInterpolator(data: Int32) -> Data {
        var out = Data()
        for value: Float in [0, 0, 0, 1, 0, 0, 0, 1] {
            out.appendFloat32(value)
        }
        out.appendUInt32(UInt32(bitPattern: data))
        return out
    }

    /// Linear quaternion keys (w first) and linear translation keys.
    public static func transformData(
        rotations: [(Float, simd_quatf)],
        translations: [(Float, SIMD3<Float>)]
    ) -> Data {
        var out = Data()
        out.appendUInt32(UInt32(rotations.count))
        if !rotations.isEmpty {
            out.appendUInt32(1)
            for (time, quaternion) in rotations {
                out.appendFloat32(time)
                out.appendFloat32(quaternion.real)
                out.appendFloat32(quaternion.imag.x)
                out.appendFloat32(quaternion.imag.y)
                out.appendFloat32(quaternion.imag.z)
            }
        }
        out.appendUInt32(UInt32(translations.count))
        if !translations.isEmpty {
            out.appendUInt32(1)
            for (time, value) in translations {
                out.appendFloat32(time)
                out.appendFloat32(value.x)
                out.appendFloat32(value.y)
                out.appendFloat32(value.z)
            }
        }
        out.appendUInt32(0) // scales
        return out
    }

    /// A camera at block 0 whose controller chain is blocks 1 to 3.
    public static func cameraFile(
        translations: [(Float, SIMD3<Float>)],
        rotations: [(Float, simd_quatf)] = [],
        start: Float = 0,
        stop: Float = 2,
        fieldOfViewControllerFirst: Bool = false
    ) -> Data {
        var fieldOfView = Data()
        fieldOfView.appendUInt32(1) // next controller: the transform controller
        fieldOfView.append(Data(count: 28))
        let first: Int32 = fieldOfViewControllerFirst ? 4 : 1
        return file(blocks: [
            Block(
                "NiCamera",
                niCamera(prefix: avObjectPrefix(controllerRef: first, translation: [1, 2, 3]))
            ),
            Block(
                "NiTransformController",
                transformController(interpolator: 2, start: start, stop: stop)
            ),
            Block("NiTransformInterpolator", transformInterpolator(data: 3)),
            Block(
                "NiTransformData",
                transformData(rotations: rotations, translations: translations)
            ),
            Block("BSFrustumFOVController", fieldOfView)
        ])
    }
}
