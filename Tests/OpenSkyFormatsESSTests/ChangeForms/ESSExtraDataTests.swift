// Every extra data layout the reader knows, read to its exact end, and the cases that stop
// the list. Bytes are built in code.

import FormatsTesting
import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESS
import TagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSExtraDataTests {
    private static func list(type: UInt8, _ payload: @Sendable (inout BinaryWriter) -> Void) throws
        -> (ESSExtraDataList, Int)
    {
        let data = ESSBytes.build { writer in
            ESSBytes.vsval(1, into: &writer)
            writer.writeUInt8(type)
            payload(&writer)
        }
        var reader = ESSReader(data)
        let list = try ESSExtraDataList.read(&reader)
        return (list, reader.bytesRemaining)
    }

    private static let nullRef: @Sendable (inout BinaryWriter) -> Void = { writer in
        ESSBytes.refID(kind: 0, value: 0, into: &writer)
    }

    private static let layouts: [(UInt8, @Sendable (inout BinaryWriter) -> Void)] = [
        (23, { _ in }),
        (24, { $0.write(Data(count: 19)) }),
        (27, { writer in
            ESSBytes.vsval(2, into: &writer)
            writer.write(Data(count: 8))
        }),
        (26, nullRef),
        (37, { $0.writeFloat32(0.5) }),
        (40, { $0.writeFloat32(12) }),
        (50, { writer in
            ESSBytes.refID(kind: 1, value: 7, into: &writer)
            ESSBytes.vsval(1, into: &writer)
            writer.write(Data(count: 4))
            ESSBytes.vsval(3, into: &writer)
            ESSBytes.vsval(2, into: &writer)
            writer.write(Data(count: 2))
        }),
        (76, { writer in
            ESSBytes.wstring("topic", into: &writer)
            writer.write(Data(count: 17))
        }),
        (91, { writer in
            ESSBytes.vsval(2, into: &writer)
            writer.write(Data(count: 12))
        }),
        (108, { $0.writeUInt8(0xFF) }),
        (153, { writer in
            nullRef(&writer)
            nullRef(&writer)
            writer.writeUInt32(UInt32(bitPattern: -2))
            ESSBytes.wstring("Sign", into: &writer)
        }),
        (153, { writer in
            ESSBytes.refID(kind: 1, value: 3, into: &writer)
            nullRef(&writer)
            writer.writeUInt32(0)
        }),
        (175, { writer in
            writer.writeUInt32(2)
            writer.write(Data(count: 14))
        })
    ]

    @Test(arguments: layouts.indices)
    func knownLayoutIsReadToItsEnd(index: Int) throws {
        let (type, payload) = Self.layouts[index]
        let (list, remaining) = try Self.list(type: type, payload)
        #expect(list.isComplete)
        #expect(list.contains(type))
        #expect(remaining == 0)
    }

    @Test func typedEntriesKeepTheirValues() throws {
        let (enchanted, _) = try Self.list(type: 155) { writer in
            ESSBytes.refID(kind: 1, value: 0x10, into: &writer)
            writer.writeUInt16(100)
        }
        #expect(enchanted.entries == [.enchantment(ESSRefID(kind: .default, value: 0x10))])
        let (aliases, _) = try Self.list(type: 136) { writer in
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x20, into: &writer)
            writer.writeUInt32(4)
        }
        #expect(aliases.entries == [.aliasInstances([
            ESSAliasInstance(quest: ESSRefID(kind: .default, value: 0x20), aliasID: 4)
        ])])
        let (health, _) = try Self.list(type: 37) { $0.writeFloat32(0.25) }
        #expect(health.entries == [.health(0.25)])
        #expect(health.entries.first?.type == 37)
    }

    @Test(arguments: [UInt8(26), 108, 200])
    func undocumentedVariantStopsTheList(type: UInt8) throws {
        let (list, _) = try Self.list(type: type) { writer in
            ESSBytes.refID(kind: 1, value: 9, into: &writer)
        }
        #expect(list.blockedBy == type)
        #expect(list.entries.isEmpty)
    }

    @Test func truncatedPayloadThrows() {
        #expect(throws: ESSError.self) {
            _ = try Self.list(type: 24) { $0.write(Data(count: 3)) }
        }
    }
}
