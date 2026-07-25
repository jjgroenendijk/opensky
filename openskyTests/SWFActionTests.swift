// ACTIONRECORD framing and operand-decode tests (milestone 8.3.1): short and
// long record headers, every ActionPush value type, the constant pool, branch
// offsets, the block-shaped actions, byte-offset seeking, and the degradations
// a malformed stream must survive. Synthetic fixtures only.

import Foundation
@testable import opensky
import Testing

struct SWFActionTests {
    private static let stopAction = SWFActionFixture.noOperands(0x07)

    @Test func framesShortAndLongRecords() {
        let data = SWFActionFixture.stream([
            Self.stopAction,
            SWFActionFixture.push([.integer(7)]),
            SWFActionFixture.noOperands(0x17)
        ])
        let block = SWFActionParser.parse(data)

        #expect(block.records.map(\.code) == [0x07, 0x96, 0x17])
        #expect(block.records.map(\.offset) == [0, 1, 9])
        #expect(block.records.map(\.endOffset) == [1, 9, 10])
        #expect(block.records[0].operandBytes.isEmpty)
        #expect(block.records[1].operandBytes.count == 5)
        #expect(block.records.map(\.carriesOperands) == [false, true, false])
        #expect(block.byteCount == 11)
        #expect(block.warnings.isEmpty)
    }

    @Test func namesOpcodesFromTheAdobeTable() {
        #expect(SWFActionName.name(forCode: 0x96) == "ActionPush")
        #expect(SWFActionName.name(forCode: 0x00) == "ActionEnd")
        #expect(SWFActionName.name(forCode: 0x8E) == "ActionDefineFunction2")
        #expect(SWFActionName.isKnown(0x60))
        #expect(!SWFActionName.isKnown(0x77))
        #expect(SWFActionName.knownCodes.count == 100)
    }

    @Test func endFlagStopsTheStreamAndTrailingBytesAreIgnored() {
        var data = SWFActionFixture.stream([Self.stopAction])
        data.append(contentsOf: [0x06, 0x04])
        let block = SWFActionParser.parse(data)

        #expect(block.records.map(\.code) == [0x07])
        #expect(block.byteCount == 2)
        #expect(block.warnings.isEmpty)
    }

    @Test func missingEndFlagIsNotAnError() {
        let data = SWFActionFixture.stream([Self.stopAction], appendEnd: false)
        let block = SWFActionParser.parse(data)

        #expect(block.records.map(\.code) == [0x07])
        #expect(block.warnings.isEmpty)
    }

    @Test func decodesEveryPushValueType() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.push([
                .string("gfx.controls.Button"), .float(1.5), .null, .undefined,
                .register(3), .boolean(true), .double(147.3), .integer(-2),
                .constant8(9), .constant16(300)
            ])
        ])
        let block = SWFActionParser.parse(data)

        #expect(
            block.records.first?.operands == .push([
                .string("gfx.controls.Button"), .float(1.5), .null, .undefined,
                .register(3), .boolean(true), .double(147.3), .integer(-2),
                .constant8(9), .constant16(300)
            ])
        )
    }

    @Test func decodesConstantPool() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.constantPool(["registerClass", "Object", ""])
        ])
        let block = SWFActionParser.parse(data)

        #expect(block.records.first?.operands == .constantPool(["registerClass", "Object", ""]))
    }

    @Test func decodesBranchOffsetsIncludingBackwardJumps() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.branch(code: 0x9D, offset: 4),
            SWFActionFixture.branch(code: 0x99, offset: -12)
        ])
        let block = SWFActionParser.parse(data)

        #expect(block.records.map(\.code) == [0x9D, 0x99])
        #expect(block.records[0].operands == .branch(offset: 4))
        #expect(block.records[1].operands == .branch(offset: -12))
    }

    @Test func seeksToRecordByteOffsets() {
        let data = SWFActionFixture.stream([
            Self.stopAction,
            SWFActionFixture.push([.integer(1)]),
            SWFActionFixture.noOperands(0x17)
        ])
        let block = SWFActionParser.parse(data)

        #expect(block.index(atOffset: 0) == 0)
        #expect(block.record(atOffset: 9)?.code == 0x17)
        // A branch landing inside the ActionPush payload resolves to nothing
        // rather than inventing an opcode.
        #expect(block.index(atOffset: 4) == nil)
        #expect(block.record(atOffset: 99) == nil)
    }

    @Test func framesDefineFunction2BodyAsFollowingRecords() throws {
        let function = SWFActionFixture.defineFunction2(
            name: "onLoad",
            parameters: [(1, "arg")],
            registerCount: 3,
            flags: [.preloadThis, .preloadRoot],
            bodySize: 2
        )
        let data = SWFActionFixture.stream([
            function, Self.stopAction, SWFActionFixture.noOperands(0x3E),
            SWFActionFixture.noOperands(0x17)
        ])
        let block = SWFActionParser.parse(data)
        guard case let .defineFunction(decoded) = block.records.first?.operands else {
            Issue.record("expected a defineFunction record: \(block.records)")
            return
        }

        #expect(decoded.name == "onLoad")
        #expect(decoded.parameterNames == ["arg"])
        #expect(decoded.parameterRegisters == [1])
        #expect(decoded.registerCount == 3)
        #expect(decoded.flags == [.preloadThis, .preloadRoot])
        #expect(decoded.bodySize == 2)

        let bodyStart = try #require(block.records.first?.endOffset)
        let body = block.records(from: bodyStart, byteCount: decoded.bodySize)
        #expect(body.map(\.code) == [0x07, 0x3E])
        #expect(block.warnings.isEmpty)
    }

    @Test func decodesDefineFunctionParameterNames() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.defineFunction(
                name: "", parameters: ["first", "second"], bodySize: 0
            )
        ])
        let block = SWFActionParser.parse(data)
        guard case let .defineFunction(decoded) = block.records.first?.operands else {
            Issue.record("expected a defineFunction record")
            return
        }

        #expect(decoded.name.isEmpty)
        #expect(decoded.parameterNames == ["first", "second"])
        #expect(decoded.parameterRegisters.isEmpty)
        #expect(decoded.registerCount == 0)
        #expect(decoded.bodySize == 0)
    }

    @Test func decodesTryWithBlock() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.tryBlock(
                catchName: "error", trySize: 1, catchSize: 1, finallySize: 0
            ),
            Self.stopAction, SWFActionFixture.noOperands(0x17)
        ])
        let block = SWFActionParser.parse(data)
        guard case let .tryBlock(decoded) = block.records.first?.operands else {
            Issue.record("expected an ActionTry record")
            return
        }

        #expect(decoded.catchName == "error")
        #expect(!decoded.catchInRegister)
        #expect(decoded.catchRegister == nil)
        #expect(decoded.hasCatchBlock)
        #expect(!decoded.hasFinallyBlock)
        #expect(decoded.trySize == 1)
        #expect(decoded.catchSize == 1)
        #expect(decoded.finallySize == 0)
        #expect(block.warnings.isEmpty)
    }

    @Test func decodesRemainingTypedOperands() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.gotoFrame(4),
            SWFActionFixture.gotoFrame2(play: true, sceneBias: 12),
            SWFActionFixture.waitForFrame(frame: 2, skipCount: 3),
            SWFActionFixture.waitForFrame2(skipCount: 5),
            SWFActionFixture.getURL(url: "FSCommand:quit", target: "_level0"),
            SWFActionFixture.getURL2(
                sendVarsMethod: 2, loadTarget: true, loadVariables: false
            ),
            SWFActionFixture.storeRegister(6),
            SWFActionFixture.setTarget("spinner"),
            SWFActionFixture.goToLabel("Start"),
            SWFActionFixture.with(bodySize: 0)
        ])
        let block = SWFActionParser.parse(data)

        #expect(block.records[0].operands == .gotoFrame(4))
        #expect(block.records[1].operands == .gotoFrame2(play: true, sceneBias: 12))
        #expect(block.records[2].operands == .waitForFrame(frame: 2, skipCount: 3))
        #expect(block.records[3].operands == .waitForFrame2(skipCount: 5))
        #expect(
            block.records[4].operands == .getURL(url: "FSCommand:quit", target: "_level0")
        )
        #expect(
            block.records[5].operands == .getURL2(
                SWFGetURL2Flags(sendVarsMethod: 2, loadTarget: true, loadVariables: false)
            )
        )
        #expect(block.records[6].operands == .storeRegister(6))
        #expect(block.records[7].operands == .setTarget("spinner"))
        #expect(block.records[8].operands == .goToLabel("Start"))
        #expect(block.records[9].operands == .with(bodySize: 0))
        #expect(block.warnings.isEmpty)
    }

    @Test func retainsUndecodedAndUnknownOpcodesAsRawBytes() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.noOperands(0x77), // not in the Adobe table
            SWFActionFixture.Action(code: 0xB1, operands: Data([1, 2, 3]))
        ])
        let block = SWFActionParser.parse(data)

        #expect(block.records.map(\.code) == [0x77, 0xB1])
        #expect(block.records.allSatisfy { $0.operands == .none })
        #expect(block.records[1].operandBytes == Data([1, 2, 3]))
        #expect(block.records.map(\.name) == [nil, nil])
        #expect(block.warnings.isEmpty)
    }

    @Test func truncatedOperandPayloadStopsTheStreamWithAWarning() {
        let block = SWFActionParser.parse(Data([0x96, 0x10, 0x00, 0x01, 0x02]))

        #expect(block.records.isEmpty)
        #expect(block.warnings == [.truncatedRecord(offset: 0, code: 0x96)])
    }

    @Test func nestedBodySizePastTheEndStopsTheStreamWithAWarning() {
        let data = SWFActionFixture.stream([SWFActionFixture.with(bodySize: 100)])
        let block = SWFActionParser.parse(data)

        #expect(block.records.map(\.code) == [0x94])
        #expect(block.warnings == [.bodySizeOutOfBounds(offset: 0, code: 0x94)])
    }

    @Test func malformedOperandsKeepTheirBytesAndFramingContinues() {
        let data = SWFActionFixture.stream([
            SWFActionFixture.Action(code: 0x96, operands: Data([0x0A])),
            Self.stopAction
        ])
        let block = SWFActionParser.parse(data)

        #expect(block.records.map(\.code) == [0x96, 0x07])
        #expect(block.records[0].operands == .none)
        #expect(block.records[0].operandBytes == Data([0x0A]))
        #expect(block.warnings == [.malformedOperands(offset: 0, code: 0x96)])
    }

    @Test func rejectsTagsItDoesNotOwn() {
        let tag = SWFTag(code: 26, body: Data())
        #expect(throws: SWFActionError.unsupportedTag(26)) {
            try SWFActionParser.parseDoAction(tag: tag)
        }
        #expect(throws: SWFActionError.unsupportedTag(26)) {
            try SWFActionParser.parseDoInitAction(tag: tag)
        }
        #expect(throws: SWFActionError.truncatedTag(59)) {
            try SWFActionParser.parseDoInitAction(tag: SWFTag(code: 59, body: Data([1])))
        }
    }
}
