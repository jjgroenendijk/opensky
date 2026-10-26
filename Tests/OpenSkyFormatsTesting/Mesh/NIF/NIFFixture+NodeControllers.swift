// Node controller blocks for `NIFNodeAnimator` tests: look-at interpolators, lag
// bones, and bone LOD. Layouts follow nif.xml; see docs/formats/nif-controllers.md.

import Foundation
import simd

extension NIFBlockFixture {
    /// `NiTransformController`: flags 0x8 is active, cycle 2 (clamp) in bits 1 and 2.
    public static func transformController(
        flags: UInt16 = 0xC, stop: Float = 1, interpolator: Int32
    ) -> Data {
        interpolatedController(flags: flags, stop: stop, interpolator: interpolator)
    }

    /// `NiLookAtInterpolator` with flags 0 (look along +X) and no sub-interpolators.
    public static func lookAtInterpolator(lookAt: Int32, flags: UInt16 = 0) -> Data {
        var out = Data()
        out.appendUInt16(flags)
        out.appendRef(lookAt)
        out.appendUInt32(0xFFFF_FFFF) // look-at name
        let unset = -Float.greatestFiniteMagnitude
        out.append(floats([unset, unset, unset, unset, unset, unset, unset, unset]))
        for _ in 0 ..< 3 {
            out.appendRef(-1)
        }
        return out
    }

    /// `BSLagBoneController`.
    public static func lagBoneController(
        linearVelocity: Float, linearRotation: Float, maximumDistance: Float
    ) -> Data {
        var out = timeController(flags: 0x8, stop: 0)
        out.append(floats([linearVelocity, linearRotation, maximumDistance]))
        return out
    }

    /// `NiBSBoneLODController` with one node list per level.
    public static func boneLODController(levels: [[Int32]]) -> Data {
        var out = timeController(flags: 0x8, stop: 0)
        out.appendUInt32(0) // current LOD
        out.appendUInt32(UInt32(levels.count))
        out.appendUInt32(0) // node group count
        for level in levels {
            out.appendUInt32(UInt32(level.count))
            for ref in level {
                out.appendRef(ref)
            }
        }
        return out
    }

    /// `BSBoneLODExtraData`: pairs of distance and bone name string index.
    public static func boneLODExtraData(_ entries: [(distance: UInt32, name: UInt32)]) -> Data {
        var out = Data()
        out.appendUInt32(UInt32(entries.count))
        for entry in entries {
            out.appendUInt32(entry.distance)
            out.appendUInt32(entry.name)
        }
        return extraData(out)
    }
}
