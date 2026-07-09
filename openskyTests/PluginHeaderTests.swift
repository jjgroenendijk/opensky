// TES4 header decode + FormID master resolution tests over synthetic
// in-code plugins (ESMFixture).

import Foundation
@testable import opensky
import Testing

struct PluginHeaderTests {
    @Test func decodesMinimalTES4() throws {
        let file = try ESMFile(data: ESMFixture.tes4())
        let header = try file.pluginHeader()
        #expect(header.stats.version == 1.71)
        #expect(header.stats.recordCount == 0)
        #expect(header.stats.nextObjectID == 0x800)
        #expect(header.flags.contains(.esm))
        #expect(!header.isLocalized)
        #expect(header.author == nil)
        #expect(header.description == nil)
        #expect(header.masters.isEmpty)
    }

    @Test func decodesAuthorDescriptionAndMasters() throws {
        let data = ESMFixture.tes4(
            flags: 0x81, // esm | localized
            author: "opensky",
            description: "synthetic fixture",
            masters: ["Skyrim.esm", "Update.esm"]
        )
        let header = try ESMFile(data: data).pluginHeader()
        #expect(header.author == "opensky")
        #expect(header.description == "synthetic fixture")
        #expect(header.masters == ["Skyrim.esm", "Update.esm"])
        #expect(header.isLocalized)
    }

    @Test func rejectsTES4WithoutHEDR() throws {
        let tes4 = ESMFixture.record("TES4", flags: 1, data: Data())
        let file = try ESMFile(data: tes4)
        #expect(throws: ESMError.malformed("TES4 record has no HEDR field")) {
            _ = try file.pluginHeader()
        }
    }

    @Test func rejectsNonTES4Record() throws {
        let data = ESMFixture.tes4()
            + ESMFixture.topGroup("GMST", contents: ESMFixture.record("GMST", data: Data()))
        let file = try ESMFile(data: data)
        let children = try #require(file.topGroup(of: "GMST")).children()
        guard case let .record(gmst)? = try children.first else {
            Issue.record("expected a record child")
            return
        }
        #expect(throws: ESMError.self) {
            _ = try PluginHeader(tes4: gmst)
        }
    }

    @Test func formIDSplitsIndexAndObjectID() {
        let id = FormID(0x0201_2345)
        #expect(id.masterIndex == 2)
        #expect(id.objectID == 0x012345)
        #expect(!id.isNull)
        #expect(id.description == "02012345")
        #expect(FormID(0).isNull)
    }

    @Test func resolvesAgainstMasterList() throws {
        let data = ESMFixture.tes4(masters: ["Skyrim.esm", "Update.esm"])
        let header = try ESMFile(data: data).pluginHeader()
        let resolver = header.formIDResolver(pluginName: "Dawnguard.esm")

        // Index 0/1 -> masters in MAST order.
        #expect(
            resolver.resolve(FormID(0x0001_3BB9))
                == ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x013BB9)
        )
        #expect(
            resolver.resolve(FormID(0x0100_0800))
                == ResolvedFormID(plugin: "Update.esm", objectID: 0x000800)
        )
        // Index == master count -> the plugin's own records.
        #expect(
            resolver.resolve(FormID(0x0200_1826))
                == ResolvedFormID(plugin: "Dawnguard.esm", objectID: 0x001826)
        )
        // Out-of-range index -> clamped to the plugin itself (xEdit behavior).
        #expect(
            resolver.resolve(FormID(0x7F00_0001))
                == ResolvedFormID(plugin: "Dawnguard.esm", objectID: 0x000001)
        )
        // Null FormID is "no reference", never a record.
        #expect(resolver.resolve(FormID(0)) == nil)
    }

    @Test func masterlessPluginResolvesToItself() {
        let resolver = FormIDResolver(pluginName: "Skyrim.esm", masters: [])
        #expect(
            resolver.resolve(FormID(0x0000_003C))
                == ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x00003C)
        )
        #expect(
            ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x00003C).description
                == "Skyrim.esm:00003C"
        )
    }
}
