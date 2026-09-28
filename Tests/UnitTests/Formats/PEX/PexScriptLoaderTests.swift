// Pure path policy and injected-load tests for compiled Papyrus scripts.

import Foundation
@testable import opensky
import Testing

@Suite("PEX script loader")
struct PexScriptLoaderTests {
    @Test(
        "canonicalizes supported script names",
        arguments: [
            ("FixtureObject", "scripts\\fixtureobject.pex"),
            ("FixtureObject.pex", "scripts\\fixtureobject.pex"),
            ("Scripts/FixtureObject", "scripts\\fixtureobject.pex"),
            ("Data\\Scripts\\FixtureObject.pex", "scripts\\fixtureobject.pex"),
            ("\\Data\\Scripts\\FixtureObject.pex", "scripts\\fixtureobject.pex")
        ]
    )
    func canonicalizes(input: String, expected: String) {
        #expect(PexScriptLoader.canonicalScriptPath(input) == expected)
    }

    @Test("rejects volume, URL and traversal forms")
    func rejectsUnsafePaths() {
        #expect(PexScriptLoader.canonicalScriptPath("C:\\Data\\Scripts\\Bad.pex") == nil)
        #expect(PexScriptLoader.canonicalScriptPath("https://example.invalid/a.pex") == nil)
        #expect(PexScriptLoader.canonicalScriptPath("Scripts\\..\\Bad.pex") == nil)
    }

    @Test("loads canonical path through the injected closure")
    func injectedLoad() throws {
        var requested: String?
        let file = try PexScriptLoader.load("FixtureObject") { path in
            requested = path
            return PexFixture.file()
        }
        #expect(requested == "scripts\\fixtureobject.pex")
        #expect(file.objects.first?.name == "FixtureObject")
    }
}
