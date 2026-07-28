// Malformed-input tests for the RDLT entry payload of the OpenSky native save
// container (issue #161): reference keys, cell locations, component ordering
// and boolean bytes.
//
// Split from OpenSkySaveCorruptionTests to stay inside the type-length limit;
// the two suites share the same rule that a defect must produce one exact,
// named `OpenSkySaveError` and never a crash.

import Foundation
@testable import opensky
import Testing

struct OpenSkySaveEntryCorruptionTests {
    // MARK: - Builders

    /// A one-entry save whose entry bytes are exactly what the caller supplies.
    private func save(entry: Data) -> Data {
        OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.deltasChunk(count: 1, entries: entry)
        ])
    }

    /// A one-entry save with a valid plugin key and no cell, carrying the
    /// caller's raw component bytes.
    private func save(componentCount: UInt8, components: Data) -> Data {
        save(entry: OpenSkySaveFixture.entryBytes(
            componentCount: componentCount,
            components: components
        ))
    }

    private func expectInvalid(_ data: Data, context: String) {
        #expect(throws: OpenSkySaveError.invalidValue(context: context)) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    private func cellBytes(_ tag: UInt8) -> Data {
        OpenSkySaveFixture.bytes([tag])
    }

    // MARK: - Keys and cells

    @Test func anUndefinedReferenceKeyKindIsRejected() {
        for tag: UInt8 in [2, 3, 0x7F, 255] {
            var writer = BinaryWriter()
            writer.writeUInt8(tag)
            writer.write(Data(count: 16))
            let entry = OpenSkySaveFixture.rawEntry(
                key: writer.data,
                cell: cellBytes(OpenSkySaveFormat.CellTag.absent),
                componentCount: 0
            )
            expectInvalid(save(entry: entry), context: "reference key kind tag \(tag)")
        }
    }

    @Test func anUndefinedCellKindIsRejected() {
        for tag: UInt8 in [3, 4, 255] {
            let entry = OpenSkySaveFixture.rawEntry(
                key: OpenSkySaveFixture.pluginKeyBytes(),
                cell: cellBytes(tag) + Data(count: 8),
                componentCount: 0
            )
            expectInvalid(save(entry: entry), context: "cell kind tag \(tag)")
        }
    }

    @Test func aReferenceKeyNameThatIsNotValidUTF8IsRejected() {
        var writer = BinaryWriter()
        writer.writeUInt8(OpenSkySaveFormat.KeyTag.plugin)
        writer.writeUInt16(2)
        writer.write(OpenSkySaveFixture.bytes([0xFF, 0xFF]))
        writer.writeUInt32(1)
        let entry = OpenSkySaveFixture.rawEntry(
            key: writer.data,
            cell: cellBytes(OpenSkySaveFormat.CellTag.absent),
            componentCount: 0
        )
        expectInvalid(save(entry: entry), context: "reference key plugin name is not valid UTF-8")
    }

    @Test func aTruncatedEntryReportsTheFieldItRanOutIn() {
        // The declared entry count promises a second entry the payload does not
        // contain, so the read fails inside the key rather than silently
        // returning one entry.
        let entry = OpenSkySaveFixture.entryBytes(componentCount: 0, components: Data())
        let data = OpenSkySaveFixture.file(chunks: [
            OpenSkySaveFixture.deltasChunk(count: 2, entries: entry + entry.prefix(4))
        ])
        #expect(throws: OpenSkySaveError.truncated(context: "reference key plugin name")) {
            try OpenSkySaveDecoder.decode(data)
        }
    }

    // MARK: - Component ordering

    @Test func aRepeatedComponentKindIsRejected() {
        let components = OpenSkySaveFixture.bytes([0, 1, 0, 1])
        expectInvalid(
            save(componentCount: 2, components: components),
            context: "component kind tag 0 is not after 0"
        )
    }

    @Test func descendingComponentKindsAreRejected() {
        // Deletion (tag 3) then enable state (tag 0).
        let components = OpenSkySaveFixture.bytes([3, 1, 0, 1])
        expectInvalid(
            save(componentCount: 2, components: components),
            context: "component kind tag 0 is not after 3"
        )
    }

    @Test func anUndefinedComponentKindIsRejected() {
        for tag: UInt8 in [4, 5, 255] {
            let components = OpenSkySaveFixture.bytes([tag]) + Data(count: 32)
            expectInvalid(
                save(componentCount: 1, components: components),
                context: "unknown component kind tag \(tag)"
            )
        }
    }

    // MARK: - Boolean bytes

    @Test func aNonBooleanEnableStateByteIsRejected() {
        for value: UInt8 in [2, 0x7F, 255] {
            let components = OpenSkySaveFixture.bytes([0, value])
            expectInvalid(
                save(componentCount: 1, components: components),
                context: "enable state has non-boolean byte \(value)"
            )
        }
    }

    @Test func aNonBooleanDeletionByteIsRejected() {
        for value: UInt8 in [2, 0x7F] {
            let components = OpenSkySaveFixture.bytes([3, value])
            expectInvalid(
                save(componentCount: 1, components: components),
                context: "deletion state has non-boolean byte \(value)"
            )
        }
    }

    @Test func aNonBooleanActivationOpenFlagIsRejected() {
        for value: UInt8 in [2, 0x7F] {
            var writer = BinaryWriter()
            writer.writeUInt8(2)
            writer.writeUInt32(7)
            writer.writeUInt8(value)
            writer.writeUInt8(0)
            expectInvalid(
                save(componentCount: 1, components: writer.data),
                context: "activation open flag has non-boolean byte \(value)"
            )
        }
    }

    @Test func aNonBooleanLastActivatorFlagIsRejected() {
        for value: UInt8 in [2, 0x7F] {
            var writer = BinaryWriter()
            writer.writeUInt8(2)
            writer.writeUInt32(7)
            writer.writeUInt8(1)
            writer.writeUInt8(value)
            expectInvalid(
                save(componentCount: 1, components: writer.data),
                context: "activation last-activator flag has non-boolean byte \(value)"
            )
        }
    }

    @Test func aNestedActivatorKeyIsValidatedLikeAnyOtherKey() {
        var writer = BinaryWriter()
        writer.writeUInt8(2)
        writer.writeUInt32(1)
        writer.writeUInt8(1)
        writer.writeUInt8(1)
        writer.writeUInt8(9) // Undefined key kind inside the activation state.
        writer.write(Data(count: 16))
        expectInvalid(
            save(componentCount: 1, components: writer.data),
            context: "reference key kind tag 9"
        )
    }

    // MARK: - Well-formed control

    @Test func theSameBuildersProduceADecodableFileWhenNothingIsBroken() throws {
        var writer = BinaryWriter()
        writer.writeUInt8(0)
        writer.writeUInt8(1)
        writer.writeUInt8(3)
        writer.writeUInt8(0)
        let file = try OpenSkySaveDecoder.decode(save(componentCount: 2, components: writer.data))
        let key = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0BAD)
        let delta = try #require(file.snapshot[key])
        #expect(delta.cell == nil)
        #expect(delta.component(ReferenceEnableState.self)?.isEnabled == true)
        #expect(delta.component(ReferenceDeletionState.self)?.isDeleted == false)
    }
}
