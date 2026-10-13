// keyboard_english.txt parsing over a small made-up file: names by scan code,
// comments, a repeated code, and lines without a hex code.

import Foundation
@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct KeyboardNameTableTests {
    @Test func readsNamesByScanCode() throws {
        let text = """
        // Name\tCode\tFlash
        Esc\t0x01\t27
        L-Ctrl\t0x1D\t17 // left control
        Slash\t0x35
        Again\t0x35
        Broken\tnone
        """
        let table = try KeyboardNameTable(data: Data(text.utf8))
        #expect(table.name(0x01) == "Esc")
        #expect(table.name(0x1D) == "L-Ctrl")
        #expect(table.name(0x35) == "Slash", "a repeated code keeps its first name")
        #expect(table.names.count == 3)
    }
}
