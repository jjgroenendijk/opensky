// The pure rules of the Runtime State panel. Synthetic values only.

import FormatsESMTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing
import WorldStateTesting

struct RuntimeStateCoreTests {
    @Test func formIDParsesHexWithOrWithoutPrefix() {
        #expect(RuntimeStateCore.parseFormID("0x0001A2B3") == FormID(0x0001_A2B3))
        #expect(RuntimeStateCore.parseFormID("  1a2b3 ") == FormID(0x0001_A2B3))
        #expect(RuntimeStateCore.parseFormID("0X10") == FormID(0x10))
    }

    @Test func formIDRejectsAnythingElse() {
        #expect(RuntimeStateCore.parseFormID("") == nil)
        #expect(RuntimeStateCore.parseFormID("0x") == nil)
        #expect(RuntimeStateCore.parseFormID("123456789") == nil)
        #expect(RuntimeStateCore.parseFormID("chest") == nil)
    }

    /// A global with no editor ID is still addressable by its key.
    @Test func unnamedGlobalFallsBackToItsKey() {
        let entry = WorldStateGlobalJournalEntry(
            sequence: 9,
            key: GlobalFixture.key(0x0000_003A),
            oldValue: nil,
            newValue: GlobalValue(type: .float, rawValue: 1.5)
        )
        #expect(
            RuntimeStateCore.globalJournalLine(entry, name: entry.key.description)
                == "9 set global test.esm:00003A = 1.5"
        )
    }

    @Test func resetGlobalLineNamesNoValue() {
        let entry = WorldStateGlobalJournalEntry(
            sequence: 4, key: GlobalFixture.key(0x3A), oldValue: nil, newValue: nil
        )
        #expect(RuntimeStateCore
            .globalJournalLine(entry, name: "TimeScale") == "4 reset global TimeScale")
    }

    @Test func integerGlobalsDropTheFraction() {
        #expect(RuntimeStateCore.globalValueText(GlobalValue(type: .short, rawValue: 4)) == "4")
        #expect(RuntimeStateCore
            .globalValueText(GlobalValue(type: .float, rawValue: 0.25)) == "0.25")
    }

    @Test func timescaleClampsIntoTheClockRange() {
        let range = GameClock.timescaleRange
        #expect(RuntimeStateCore.clampTimescale(range.upperBound + 1) == range.upperBound)
        #expect(RuntimeStateCore.clampTimescale(range.lowerBound - 1) == range.lowerBound)
        #expect(RuntimeStateCore.clampTimescale(20) == 20)
    }

    @Test func typeNamesMatchTheAuthoredTypes() {
        #expect(RuntimeStateCore.globalTypeName(.short) == "short")
        #expect(RuntimeStateCore.globalTypeName(.long) == "long")
        #expect(RuntimeStateCore.globalTypeName(.float) == "float")
    }

    @Test func globalNamesMapKeysToEditorIDs() throws {
        let store = try GlobalFixture.store(
            GlobalFixture.record(formID: 0x3A, editorID: "TimeScale", type: .short, value: 20)
        )
        #expect(RuntimeStateCore.globalNamesByKey(store) == [GlobalFixture.key(0x3A): "TimeScale"])
        #expect(RuntimeStateCore.globalNamesByKey(nil).isEmpty)
    }
}
