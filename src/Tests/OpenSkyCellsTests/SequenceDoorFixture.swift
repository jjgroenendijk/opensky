// A synthetic gate mesh: a root, one leaf at (10, 0, 0), and `Open` and `Close`
// sequences that raise and lower the leaf by 100 units in one second. Layouts per
// NifTools nif.xml; docs/formats/nif-sequences.md.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting

enum SequenceDoorFixture {
    static let strings = [
        "Gate", "Leaf", "Open", "Close", "NiTransformController", "start", "Sound: GateOpen", "end"
    ]

    /// Blocks: 0 root, 1 leaf, 2 to 5 the two interpolators and their keys, 6 the open
    /// text keys, 7 `Open`, 8 `Close`.
    static func file(withClose: Bool = true) -> Data {
        var blocks = [
            NIFFixture.Block("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 0), children: [1]
            )),
            NIFFixture.Block("NiNode", NIFFixture.niNode(
                prefix: NIFFixture.avObjectPrefix(nameIndex: 1, translation: [10, 0, 0])
            )),
            NIFFixture.Block("NiTransformInterpolator", interpolator(data: 3)),
            NIFFixture.Block("NiTransformData", rise(from: 0, to: 100)),
            NIFFixture.Block("NiTransformInterpolator", interpolator(data: 5)),
            NIFFixture.Block("NiTransformData", rise(from: 100, to: 0)),
            NIFFixture.Block("NiTextKeyExtraData", textKeys()),
            NIFFixture.Block("NiControllerSequence", sequence(name: 2, interpolator: 2, keys: 6))
        ]
        if withClose {
            blocks.append(NIFFixture.Block(
                "NiControllerSequence", sequence(name: 3, interpolator: 4, keys: -1)
            ))
        }
        return NIFFixture.file(blocks: blocks, strings: strings)
    }

    /// Every pose part unset (`#INV_FLT#`), then the keys.
    private static func interpolator(data: UInt32) -> Data {
        var out = Data()
        for _ in 0 ..< 8 {
            out.appendFloat32(NIFParticleControllerDecoder.invalidFloat)
        }
        out.appendUInt32(data)
        return out
    }

    /// No rotation keys, two linear translation keys at (10, 0, z), no scale keys.
    private static func rise(from start: Float, to end: Float) -> Data {
        var out = Data()
        out.appendUInt32(0)
        out.appendUInt32(2)
        out.appendUInt32(1)
        for (time, z) in [(Float(0), start), (1, end)] {
            out.appendFloat32(time)
            out.appendFloat32(10)
            out.appendFloat32(0)
            out.appendFloat32(z)
        }
        out.appendUInt32(0)
        return out
    }

    private static func textKeys() -> Data {
        var out = Data()
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(3)
        for (time, string) in [(Float(0), UInt32(5)), (0, 6), (1, 7)] {
            out.appendFloat32(time)
            out.appendUInt32(string)
        }
        return out
    }

    /// One controlled block on `Leaf`, then weight, text keys, clamp, frequency 1, 0 to 1 s.
    private static func sequence(name: UInt32, interpolator: UInt32, keys: Int32) -> Data {
        var out = Data()
        out.appendUInt32(name)
        out.appendUInt32(1)
        out.appendUInt32(1)
        out.appendUInt32(interpolator)
        out.appendUInt32(UInt32.max)
        out.append(0)
        for string in [1, UInt32.max, 4, UInt32.max, UInt32.max] {
            out.appendUInt32(string)
        }
        out.appendFloat32(1)
        out.appendUInt32(UInt32(bitPattern: keys))
        out.appendUInt32(2)
        out.appendFloat32(1)
        out.appendFloat32(0)
        out.appendFloat32(1)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt32(0xFFFF_FFFF)
        out.appendUInt16(0)
        return out
    }
}
