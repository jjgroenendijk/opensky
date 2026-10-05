// Synthetic SNDR, SNCT and ASPC plugins, built in code with ESMFixture.

@testable import FormatsTesting
import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM

/// Synthetic audio plugins for the interior and exterior transition suites: a
/// multi-descriptor SNDR store and a one-record ASPC store.
@MainActor
public enum TransitionAudioFixture {
    /// One SNDR per entry, each naming a single ANAM track. Sound references
    /// resolve straight to SNDR (`resolveAny`), which is what vanilla door and
    /// region records do.
    public static func makeSoundStore(descriptors: [(id: UInt32, track: String)])
        -> SoundRecordStore
    {
        let categoryID: UInt32 = 0xB00
        var bytes = Data()
        for descriptor in descriptors {
            let fields = ESMFixture.field("GNAM", uint32(categoryID))
                + ESMFixture.field("ANAM", ESMFixture.zstring(descriptor.track))
            bytes += ESMFixture.record("SNDR", formID: descriptor.id, data: fields)
        }
        let category = ESMFixture.field(
            "EDID", ESMFixture.zstring(AudioCategory.effects.soundCategoryEditorID)
        ) + ESMFixture.field("FNAM", uint32(2))
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup("SNDR", contents: bytes)
            + ESMFixture.topGroup(
                "SNCT",
                contents: ESMFixture.record("SNCT", formID: categoryID, data: category)
            )
        do {
            return try SoundRecordStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }

    private static func uint32(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }

    /// One ASPC whose SNAM names the interior's direct ambient sound.
    public static func makeAcousticSpaceStore(
        id: UInt32,
        ambientSound: UInt32
    ) -> AcousticSpaceStore {
        var snam = Data()
        snam.appendUInt32(ambientSound)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Aspc\(id)"))
            + ESMFixture.field("SNAM", snam)
        let plugin = ESMFixture.tes4() + ESMFixture.topGroup(
            "ASPC", contents: ESMFixture.record("ASPC", formID: id, data: fields)
        )
        do {
            return try AcousticSpaceStore(file: ESMFile(data: plugin))
        } catch {
            preconditionFailure("synthetic fixture failed: \(error)")
        }
    }
}
