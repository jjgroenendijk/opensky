// `openskycli pex-calls` finds every call of one function name, over synthetic bytecode only.

import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite("PEX call sites", .tags(.parser))
struct PexCallSitesTests {
    @Test("finds a method call without case, with its place and operands")
    func findsAMethodCall() throws {
        let file = try PexDecoder.file(from: PexFixture.file())
        let sites = PexCallSites.find("METHOD", in: file)
        #expect(sites.count == 1)
        let site = try #require(sites.first)
        #expect(site.objectName == "FixtureObject")
        #expect(site.stateName == "state")
        #expect(site.callerName == "function")
        #expect(site.instructionIndex == 23)
        #expect(site.opcode == .callMethod)
        #expect(PexCallSites.line(site)
            == "FixtureObject \"state\" function#23 callmethod method, _self, result, 2, "
            + "\"literal\", true")
    }

    @Test("reads the called name from the place each call opcode keeps it")
    func readsEachCallOpcode() throws {
        let file = try PexDecoder.file(from: PexFixture.file())
        #expect(PexCallSites.find("parentCall", in: file).map(\.opcode) == [.callParent])
        #expect(PexCallSites.find("staticCall", in: file).map(\.opcode) == [.callStatic])
        #expect(PexCallSites.find("StaticClass", in: file).isEmpty)
        #expect(PexCallSites.find("missing", in: file).isEmpty)
    }
}
