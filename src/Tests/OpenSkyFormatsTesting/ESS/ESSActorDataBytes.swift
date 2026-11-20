// The change data of an actor reference with no flagged fields: the actor header, then,
// for an actor with no AI process, the actor data after the animation part.
// See docs/formats/ess-change-forms.md#actor-data-after-the-animation-part.

public import Foundation
import OpenSkyFormatsCore

public enum ESSActorDataBytes {
    /// `damage` is the health damage modifier. A movement flag other than 0 ends the
    /// bytes there, as a reader stops at it.
    public static func actor(
        processLevel: UInt32 = 0xFFFF_FFFF, lifeState: UInt8, damage: Float = 0,
        movement: UInt8 = 0
    ) -> Data {
        ESSBytes.build { writer in
            writer.writeUInt32(processLevel)
            writer.writeUInt32(0)
            writer.write(Data(count: 53))
            ESSBytes.refID(kind: 1, value: 0x14, into: &writer)
            writer.writeUInt16(0)
            writer.write(Data(count: 2))
            writer.writeUInt8(lifeState)
            writer.write(Data(count: 11))
            ESSBytes.refID(kind: 0, value: 0, into: &writer)
            writer.writeUInt8(0)
            for _ in 0 ..< 5 {
                ESSBytes.refID(kind: 0, value: 0, into: &writer)
            }
            for modifier: Float in [damage, 0, 0, 0] {
                writer.writeUInt32(3)
                writer.writeFloat32(10)
                writer.writeFloat32(0)
                writer.writeFloat32(modifier)
            }
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.vsval(0, into: &writer)
            writer.writeUInt32(0)
            writer.writeUInt8(movement)
            guard movement == 0 else { return }
            writer.writeUInt32(0)
            writer.writeUInt8(0)
            writer.writeUInt32(0)
            writer.write(Data(count: 8))
            ESSBytes.refID(kind: 0, value: 0, into: &writer)
            writer.writeUInt8(0)
        }
    }
}
