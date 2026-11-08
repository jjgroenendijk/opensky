// The executable version reader, over executables built in code.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct PEVersionInfoTests {
    @Test func readsTheFourPartFileVersion() throws {
        var fixture = PEFixture()
        fixture.version = [1, 6, 1170, 0]
        let version = try PEVersionInfo.fileVersion(data: fixture.build())
        #expect(version == PEFileVersion(1, 6, 1170, 0))
        #expect(version.description == "1.6.1170.0")
    }

    @Test func skipsOtherResourceTypes() throws {
        var fixture = PEFixture()
        fixture.otherResourceType = 3
        fixture.version = [1, 5, 97, 0]
        #expect(try PEVersionInfo.fileVersion(data: fixture.build()) == PEFileVersion(1, 5, 97, 0))
    }

    @Test func failsWithoutAVersionResource() {
        var fixture = PEFixture()
        fixture.otherResourceType = 3
        fixture.includesVersion = false
        #expect(throws: PEVersionError.noVersionResource) {
            try PEVersionInfo.fileVersion(data: fixture.build())
        }
    }

    @Test func failsOnABadSignature() {
        var fixture = PEFixture()
        fixture.signature = 0x1234_5678
        #expect(throws: PEVersionError.self) { try PEVersionInfo.fileVersion(data: fixture.build())
        }
    }

    @Test func failsOnShortOrForeignBytes() {
        #expect(throws: PEVersionError.notAnExecutable) {
            try PEVersionInfo.fileVersion(data: Data("ELF!".utf8))
        }
        #expect(throws: PEVersionError.self) {
            try PEVersionInfo.fileVersion(data: PEFixture().build().prefix(0x50))
        }
    }

    @Test func versionsCompareByPart() {
        #expect(PEFileVersion(1, 5, 97, 0) < PEFileVersion(1, 6, 640, 0))
        #expect(PEFileVersion(1, 6, 640, 0) < PEFileVersion(1, 6, 1170, 0))
    }
}
