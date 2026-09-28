// Havok packfile (HKX) container decode tests over synthetic in-code files
// (HKXFixture) — never extracted game files (AGENTS.md "Legal & IP boundary").
// Byte map: docs/formats/hkx-container.md.

import Foundation
@testable import opensky
import Testing

struct HKXFileTests {
    /// Runs the parser, returning a thrown HKXError (nil on success or a
    /// non-HKX error such as reader truncation).
    private func hkxError(_ data: Data) -> HKXError? {
        do {
            _ = try HKXFile(data: data)
            return nil
        } catch let error as HKXError {
            return error
        } catch {
            return nil
        }
    }

    // MARK: - Happy path

    @Test func decodesHeaderFields() throws {
        let fixture = HKXFixture()
        let file = try HKXFile(data: fixture.build())
        let header = file.header
        #expect(header.userTag == 0x1234_5678)
        #expect(header.fileVersion == 8)
        #expect(header.pointerSize == 8)
        #expect(header.isLittleEndian)
        #expect(!header.reusePaddingOptimization)
        #expect(header.emptyBaseClassOptimization)
        #expect(header.sectionCount == 3)
        #expect(header.contentsSectionIndex == 2)
        #expect(header.contentsSectionOffset == 0)
        #expect(header.contentsClassNameSectionIndex == 0)
        #expect(header.contentsClassNameOffset == fixture.rootNameOffset)
        #expect(header.versionString == "hk_2010.2.0-r1")
        #expect(header.flags == 0)
    }

    @Test func decodesThreeSectionHeaders() throws {
        let fixture = HKXFixture()
        let file = try HKXFile(data: fixture.build())
        #expect(file.sections.map(\.header.name) == ["__classnames__", "__types__", "__data__"])

        let classnames = file.sections[0].header
        // No fixups: every relative offset equals the blob length.
        #expect(classnames.localFixupsOffset == classnames.endOffset)
        #expect(classnames.endOffset == fixture.classNamesBlob.count)

        let types = file.sections[1].header
        #expect(types.endOffset == 0)
        #expect(types.dataStart == file.sections[2].header.dataStart) // shared start

        let data = file.sections[2].header
        #expect(data.localFixupsOffset == fixture.dataPayloadSize) // payload precedes fixups
        #expect(data.dataSize == fixture.dataPayloadSize)
        #expect(data.localFixupsOffset < data.globalFixupsOffset)
        #expect(data.globalFixupsOffset < data.virtualFixupsOffset)
    }

    @Test func decodesClassNamesWithNameOffsets() throws {
        let fixture = HKXFixture()
        let file = try HKXFile(data: fixture.build())
        #expect(file.classNames.map(\.name) == ["hkClass", "hkClassMember", "hkRootLevelContainer"])
        #expect(file.classNames.map(\.signature) == [0x0BD4_C87B, 0x0B5F_0E29, 0x6DAB_825E])
        // nameOffset = entry start + 5 (u32 signature + 0x09 separator).
        #expect(file.classNames.map(\.nameOffset) == [5, 18, 37])
    }

    @Test func classNameTableStopsAtSentinel() throws {
        // Trailing 0xFFFFFFFF + 0xFF padding after the entries must not become
        // phantom class names.
        let fixture = HKXFixture()
        let file = try HKXFile(data: fixture.build())
        #expect(file.classNames.count == fixture.classNames.count)
    }

    @Test func decodesFixupTables() throws {
        let fixture = HKXFixture()
        let file = try HKXFile(data: fixture.build())
        let section = file.sections[2]
        #expect(section.localFixups == [HKXLocalFixup(fromOffset: 0, toOffset: 16)])
        #expect(section.globalFixups == [HKXGlobalFixup(
            fromOffset: 4,
            sectionIndex: 2,
            toOffset: 32
        )])
        // Default file registers one root object as a virtual fixup.
        let virtual = try #require(section.virtualFixups.first)
        #expect(virtual.dataOffset == 0)
        #expect(virtual.classNameSectionIndex == 0)
        #expect(virtual.classNameOffset == fixture.rootNameOffset)
    }

    @Test func fixupTailPaddingDoesNotAddEntries() throws {
        // Aligning each region to 16 bytes leaves a 0xFFFFFFFF sentinel tail;
        // the table must still decode exactly its real entries.
        var fixture = HKXFixture()
        fixture.alignFixupRegions = true
        let file = try HKXFile(data: fixture.build())
        let section = file.sections[2]
        #expect(section.localFixups == [HKXLocalFixup(fromOffset: 0, toOffset: 16)])
        #expect(section.globalFixups.count == 1)
        #expect(section.virtualFixups.count == 1)
    }

    @Test func objectsResolveClassNames() throws {
        var fixture = HKXFixture()
        // Second object -> hkClass; third references an unknown offset.
        fixture.virtualFixups = [
            .init(
                dataOffset: 24,
                classNameSection: 0,
                classNameOffset: UInt32(fixture.nameOffset(ofClass: 0))
            ),
            .init(dataOffset: 36, classNameSection: 0, classNameOffset: 9999)
        ]
        let file = try HKXFile(data: fixture.build())
        let objects = file.objects
        #expect(objects.count == 3)
        #expect(objects[0].className == "hkRootLevelContainer")
        #expect(objects[0].signature == 0x6DAB_825E)
        #expect(objects[0].sectionIndex == 2)
        #expect(objects[1].className == "hkClass")
        #expect(objects[1].signature == 0x0BD4_C87B)
        // Dangling classNameOffset stays inspectable, resolves to nil.
        #expect(objects[2].className == nil)
        #expect(objects[2].signature == nil)
        #expect(objects[2].dataOffset == 36)
    }

    @Test func rootClassNameResolves() throws {
        let fixture = HKXFixture()
        let file = try HKXFile(data: fixture.build())
        let root = try #require(file.rootClassName)
        #expect(root.name == "hkRootLevelContainer")
        #expect(root.nameOffset == fixture.rootNameOffset)
    }

    @Test func sectionDataSlicesPayload() throws {
        let fixture = HKXFixture()
        let file = try HKXFile(data: fixture.build())
        #expect(try file.sectionData(at: 2) == fixture.payloadBytes) // object data, fixups excluded
        #expect(try file.sectionData(at: 0) == fixture.classNamesBlob)
    }

    // MARK: - Malformed input

    @Test func rejectsBadMagic() {
        var fixture = HKXFixture()
        fixture.badMagic = true
        #expect(hkxError(fixture.build()) == .badMagic(
            found0: 0xDEAD_BEEF,
            found1: HKXHeader.magic1
        ))
    }

    @Test func rejectsNon64BitPointer() {
        var fixture = HKXFixture()
        fixture.pointerSize = 4
        #expect(hkxError(fixture.build()) == .unsupportedLayout(pointerSize: 4, littleEndian: 1))
    }

    @Test func rejectsAbsurdSectionCount() {
        var fixture = HKXFixture()
        fixture.sectionCountOverride = 9999
        #expect(hkxError(fixture.build()) == .sectionCountOutOfRange(9999))
    }

    @Test func rejectsTruncatedFile() throws {
        var fixture = HKXFixture()
        fixture.truncateTo = 40 // cut off inside the 64-byte header
        #expect(throws: BinaryReaderError.self) { try HKXFile(data: fixture.build()) }
    }

    @Test func rejectsSectionEndBeyondEOF() throws {
        var fixture = HKXFixture()
        fixture.dataEndOffsetOverride = 100_000
        let error = try #require(hkxError(fixture.build()))
        guard case .sectionOutOfBounds = error else {
            Issue.record("expected sectionOutOfBounds, got \(error)")
            return
        }
    }

    @Test func rejectsDescendingFixupOffsets() {
        var fixture = HKXFixture()
        fixture.nonAscendingFixups = true
        #expect(hkxError(fixture.build()) == .fixupRangeInvalid(section: "__data__"))
    }

    @Test func rejectsContentsIndexOutOfRange() {
        var fixture = HKXFixture()
        fixture.contentsSectionIndex = 5 // only sections 0...2 exist
        #expect(hkxError(fixture.build()) == .sectionIndexInvalid(5))
    }

    @Test func stopsClassNamesOnBadSeparator() throws {
        // A separator byte other than 0x09 ends the table early (0xFF tail
        // padding uses this); the file still parses.
        var fixture = HKXFixture()
        fixture.badClassNameSeparator = true
        let file = try HKXFile(data: fixture.build())
        #expect(file.classNames.map(\.name) == ["hkClass"])
    }
}
