// `openskycli pex` prints a compiled script as text, over synthetic bytecode only.

import Foundation
@testable import OpenSkyFormatsPEX
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite("PEX disassembly", .tags(.parser))
struct PexDisassemblyTests {
    @Test("prints the object, its members, and each instruction with its operands")
    func printsTheWholeScript() throws {
        let lines = try PexDisassembly.lines(of: PexFile(data: PexFixture.file()))
        let strings = PexFixture.strings.count
        #expect(lines.first == "script FixtureObject.psc (PEX 3.2, \(strings) strings)")
        #expect(lines.contains("object FixtureObject extends ParentObject"))
        #expect(lines.filter { $0.hasPrefix("  variable ") }.count == 6)
        #expect(lines
            .contains { $0.hasPrefix("  property ") && $0.hasSuffix(" auto(::property_var)") })
        #expect(lines.contains("  state \"state\""))
        #expect(lines.contains("      local Int local"))
        #expect(lines.contains {
            $0.hasPrefix("    function ") && $0.contains("function(Int parameter)")
        })
        #expect(lines.contains("      0 nop"))
        #expect(lines
            .contains { $0.hasPrefix("      23 callmethod ") && $0.hasSuffix("\"literal\", true") })
    }

    @Test("keeps only the named function, without case")
    func filtersOneFunction() throws {
        let file = try PexFile(data: PexFixture.file())
        let lines = PexDisassembly.lines(of: file, function: "FUNCTION")
        #expect(lines.contains("  state \"state\""))
        #expect(!lines.contains { $0.hasPrefix("  property ") })
        #expect(PexDisassembly.lines(of: file, function: "missing").count == 2)
    }

    @Test("writes each value kind the way a script spells it")
    func spellsValues() {
        #expect(PexDisassembly.text(.null) == "none")
        #expect(PexDisassembly.text(.identifier("akActor")) == "akActor")
        #expect(PexDisassembly.text(.string("Sequence1")) == "\"Sequence1\"")
        #expect(PexDisassembly.text(.integer(-42)) == "-42")
        #expect(PexDisassembly.text(.float(3.5)) == "3.5")
        #expect(PexDisassembly.text(.boolean(true)) == "true")
    }
}
