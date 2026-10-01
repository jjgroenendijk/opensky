// The package reconcile input when plugin data repeats an actor key.
// Synthetic records only.

@testable import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct PackageResidentBasesTests {
    private static let actor: UInt32 = 0x500
    private static let other: UInt32 = 0x501

    @Test func repeatedKeyKeepsTheFirstEntryWithoutTrapping() throws {
        let entries = try [
            Self.entry(Self.actor, base: 0x101),
            Self.entry(Self.other, base: 0x303),
            Self.entry(Self.actor, base: 0x202)
        ]

        let bases = ActorPackageRuntime.residentBases(entries)

        #expect(bases == [Self.key(Self.actor): FormID(0x101), Self.key(Self.other): FormID(0x303)])
    }

    @Test func nonActorEntriesAreLeftOut() throws {
        let reference = try PlacedReference(record: ESMFixture.parseRecord(ESMFixture.record(
            "REFR",
            formID: 0x600,
            data: ESMFixture.field("NAME", Self.formIDData(0x700))
                + ESMFixture.field("DATA", Data(count: 24))
        )))
        let entries = [RuntimeReferenceEntry(
            key: Self.key(0x600),
            formID: FormID(0x600),
            isPersistent: false,
            record: .reference(reference)
        )]

        #expect(ActorPackageRuntime.residentBases(entries).isEmpty)
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    private static func entry(_ objectID: UInt32, base: UInt32) throws -> RuntimeReferenceEntry {
        let fields = ESMFixture.field("NAME", formIDData(base))
            + ESMFixture.field("DATA", Data(count: 24))
        let actor = try PlacedActor(record: ESMFixture.parseRecord(
            ESMFixture.record("ACHR", formID: objectID, data: fields)
        ))
        return RuntimeReferenceEntry(
            key: key(objectID), formID: FormID(objectID), isPersistent: true, record: .actor(actor)
        )
    }

    private static func formIDData(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
