// controlmap.txt parsing over a small made-up file: contexts, inputs, the remap
// flag, references, and malformed lines.

import Foundation
@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ControlMapFileTests {
    private static let text = """
    // Event\tKeyboard\tMouse\tGamepad\tRemapKey\tRemapMouse\tRemapPad
    // Main Gameplay
    Forward\t0x11\t0xff\t0xff\t1\t0\t0
    Pause\t0x01\t0xff\t0x0010\t0\t0\t0\t0x8
    Sneak\t0x1d+0xb7\t0xff\t0xff\t1\t0\t0

    // Menu Mode
    Accept\t!0,Forward\t0x00\t0xff\t0\t0\t0
    """

    private static func parse(_ text: String) throws(ControlMapError) -> ControlMapFile {
        try ControlMapFile(data: Data(text.utf8))
    }

    @Test func readsContextsInputsAndTheKeyboardRemapFlag() throws {
        let file = try Self.parse(Self.text)
        #expect(file.contexts.map(\.name) == ["Main Gameplay", "Menu Mode"])
        let gameplay = try #require(file.context(named: "Main Gameplay"))
        #expect(gameplay.event(named: "Forward")?.keyboard == [.code(0x11)])
        #expect(gameplay.event(named: "Forward")?.mouse.isEmpty == true)
        #expect(gameplay.event(named: "Forward")?.remappableKeyboard == true)
        #expect(gameplay.event(named: "Pause")?.remappableKeyboard == false)
        #expect(gameplay.event(named: "Sneak")?.keyboard == [.chord([0x1D, 0xB7])])
    }

    @Test func referencesResolveToTheOtherContextsCodes() throws {
        let file = try Self.parse(Self.text)
        let menu = try #require(file.context(named: "Menu Mode"))
        let accept = menu.event(named: "Accept")
        #expect(accept?.keyboard == [.reference(context: 0, event: "Forward")])
        #expect(file.codes(of: "Accept", in: 1, device: .keyboard) == [0x11])
    }

    @Test func malformedLinesThrowWithTheirLineNumber() {
        #expect(throws: ControlMapError.malformedLine(
            line: 1, reason: "3 fields, expected at least 7"
        )) { try Self.parse("Forward\t0x11\t0xff") }
        #expect(throws: ControlMapError.malformedLine(line: 1, reason: "remap flag 2")) {
            try Self.parse("Forward\t0x11\t0xff\t0xff\t2\t0\t0")
        }
        #expect(throws: ControlMapError.malformedLine(line: 1, reason: "group flags zz")) {
            try Self.parse("Forward\t0x11\t0xff\t0xff\t1\t0\t0\tzz")
        }
    }
}
