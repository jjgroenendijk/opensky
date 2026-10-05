// The package reconcile input when plugin data repeats an actor key.
// Synthetic records only.

@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct PackageResidentBasesTests {
    private static let actor: UInt32 = 0x500
    private static let other: UInt32 = 0x501

    @Test func repeatedKeyKeepsTheFirstEntryWithoutTrapping() throws {
        let entries = try [
            PackageRuntimeFixture.residentActor(Self.actor, base: 0x101),
            PackageRuntimeFixture.residentActor(Self.other, base: 0x303),
            PackageRuntimeFixture.residentActor(Self.actor, base: 0x202)
        ]

        let bases = ActorPackageRuntime.residentBases(entries)

        #expect(bases == [
            PackageRuntimeFixture.key(Self.actor): FormID(0x101),
            PackageRuntimeFixture.key(Self.other): FormID(0x303)
        ])
    }

    @Test func nonActorEntriesAreLeftOut() throws {
        let reference = try PlacedReference(record: ESMFixture.parseRecord(ESMFixture.record(
            "REFR",
            formID: 0x600,
            data: ESMFixture.field("NAME", PackageRuntimeFixture.formIDData(0x700))
                + ESMFixture.field("DATA", Data(count: 24))
        )))
        let entries = [RuntimeReferenceEntry(
            key: PackageRuntimeFixture.key(0x600),
            formID: FormID(0x600),
            isPersistent: false,
            record: .reference(reference)
        )]

        #expect(ActorPackageRuntime.residentBases(entries).isEmpty)
    }
}
