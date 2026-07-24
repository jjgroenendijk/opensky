// `SWFActionInventory` (milestone 8.3.1 stage 2): opcode frequency, unknown
// opcodes, the structural host/GFx-API name heuristic (immediately preceding
// pushed value, constant-pool resolved), clip-event usage, function/structure
// stats, and DoAction/DoInitAction/ClipActions block-kind counts, over
// synthetic fixtures only (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct SWFActionInventoryTests {
    @Test func opcodeFrequencyAndUnknownOpcodesAreTallied() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFActionFixture.doActionTag([
                SWFActionFixture.noOperands(0x07), // ActionStop: known
                SWFActionFixture.noOperands(0x77), // not in the Adobe table
                SWFActionFixture.noOperands(0x9E) // ActionCall: known, no typed decode
            ]),
            SWFDisplayFixture.showFrameTag
        ])
        var inventory = SWFActionInventory()

        inventory.record(movie, path: "a.swf")

        #expect(inventory.opcodeCounts[0x07] == 1)
        #expect(inventory.opcodeMovies[0x07] == ["a.swf"])
        #expect(inventory.unknownOpcodeMovies[0x77] == ["a.swf"])
        #expect(inventory.unknownOpcodeMovies[0x9E] == nil)
        #expect(inventory.distinctOpcodeCount == 3)
        #expect(inventory.movies.count == 1)
        let summary = try #require(inventory.movies.first)
        #expect(summary.path == "a.swf")
        #expect(summary.actionBlocks == 1)
        #expect(summary.actionRecords == 3)
        #expect(summary.distinctOpcodes == 3)
        #expect(summary.unknownOpcodes == 1)
        #expect(summary.undecodedOpcodes == 1)
        #expect(summary.warnings == 0)
    }

    @Test func hostAPINamesResolveFromPrecedingPushAndConstantPool() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFActionFixture.doActionTag([
                SWFActionFixture.push([.string("obj"), .string("member")]),
                SWFActionFixture.noOperands(0x4E), // ActionGetMember
                SWFActionFixture.constantPool(["alpha", "beta"]),
                SWFActionFixture.push([.constant8(1)]),
                SWFActionFixture.noOperands(0x4F), // ActionSetMember
                SWFActionFixture.push([.integer(5)]),
                SWFActionFixture.noOperands(0x52) // ActionCallMethod: not a name, ignored
            ]),
            SWFDisplayFixture.showFrameTag
        ])
        var inventory = SWFActionInventory()

        inventory.record(movie, path: "b.swf")

        #expect(inventory.hostNameCounts["member"] == 1)
        #expect(inventory.hostNameMovies["member"] == ["b.swf"])
        #expect(inventory.hostNameCounts["beta"] == 1)
        #expect(inventory.hostNameCounts.count == 2)
        #expect(inventory.constantPoolCount == 1)
        #expect(inventory.maxConstantPoolSize == 2)
    }

    @Test func clipEventsAndBlockKindsAreCountedByHandler() throws {
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.clipActions = SWFActionFixture.clipActions(
            version: 6,
            allEvents: [.press, .construct],
            handlers: [
                SWFActionFixture.ClipHandler(
                    events: [.press],
                    actions: SWFActionFixture.stream(
                        [SWFActionFixture.noOperands(0x07)], appendEnd: false
                    )
                ),
                SWFActionFixture.ClipHandler(
                    events: [.construct],
                    actions: SWFActionFixture.stream(
                        [SWFActionFixture.noOperands(0x06)], appendEnd: false
                    )
                )
            ]
        )
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x07)]),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFActionFixture.doInitActionTag(spriteId: 99, [SWFActionFixture.noOperands(0x06)]),
            SWFDisplayFixture.showFrameTag
        ])
        var inventory = SWFActionInventory()

        inventory.record(movie, path: "c.swf")

        #expect(inventory.clipEventCounts["press"] == 1)
        #expect(inventory.clipEventCounts["construct"] == 1)
        #expect(inventory.clipEventMovies["press"] == ["c.swf"])
        #expect(inventory.doActionBlockCount == 1)
        #expect(inventory.clipActionBlockCount == 2)
        #expect(inventory.doInitActionBlockCount == 1)
    }

    @Test func functionAndStructureStatsAreTracked() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFActionFixture.doActionTag([
                SWFActionFixture.defineFunction(name: "f1", parameters: [], bodySize: 0),
                SWFActionFixture.defineFunction2(
                    name: "f2",
                    parameters: [(1, "a")],
                    registerCount: 4,
                    flags: [],
                    bodySize: 0
                ),
                SWFActionFixture.with(bodySize: 0),
                SWFActionFixture.tryBlock(
                    catchName: "e", trySize: 0, catchSize: 0, finallySize: 0
                )
            ]),
            SWFDisplayFixture.showFrameTag
        ])
        var inventory = SWFActionInventory()

        inventory.record(movie, path: "d.swf")

        #expect(inventory.defineFunctionCount == 1)
        #expect(inventory.defineFunction2Count == 1)
        #expect(inventory.maxRegisterCount == 4)
        #expect(inventory.withCount == 1)
        #expect(inventory.tryCount == 1)
        #expect(inventory.maxBlockRecords == 4)
        #expect(inventory.maxBlockBytes > 0)
    }

    @Test func multipleMoviesAccumulateAcrossRecordCalls() throws {
        let movieA = try SWFDisplayFixture.movie(tags: [
            SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x07)]),
            SWFDisplayFixture.showFrameTag
        ])
        let movieB = try SWFDisplayFixture.movie(tags: [
            SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x07)]),
            SWFDisplayFixture.showFrameTag
        ])
        var inventory = SWFActionInventory()

        inventory.record(movieA, path: "a.swf")
        inventory.record(movieB, path: "b.swf")

        #expect(inventory.opcodeCounts[0x07] == 2)
        #expect(inventory.opcodeMovies[0x07]?.count == 2)
        #expect(inventory.movies.count == 2)
    }
}
