// Synthetic DefineButton2, DefineScalingGrid, FileAttributes, and Metadata tags,
// built from the Adobe SWF File Format Specification v19 — never extracted game
// files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import OpenSkyFormatsSWF

public enum SWFButtonFixture: Sendable {
    /// One BUTTONRECORD with an identity MATRIX and CXFORMWITHALPHA.
    public struct Record: Sendable {
        public var states: SWFButtonStates
        public var characterId: UInt16
        public var depth: UInt16

        public init(states: SWFButtonStates, characterId: UInt16, depth: UInt16) {
            self.states = states
            self.characterId = characterId
            self.depth = depth
        }
    }

    /// One BUTTONCONDACTION: the first flag byte, the key/OverDownToIdle byte,
    /// and the actions.
    public struct Condition: Sendable {
        public var transitions: UInt8
        public var keyByte: UInt8
        public var actions: [SWFActionFixture.Action]

        public init(transitions: UInt8, keyByte: UInt8 = 0, actions: [SWFActionFixture.Action]) {
            self.transitions = transitions
            self.keyByte = keyByte
            self.actions = actions
        }
    }

    public static func defineButton2Tag(
        characterId: UInt16,
        trackAsMenu: Bool = false,
        records: [Record],
        conditions: [Condition] = []
    ) -> SWFFixture.Tag {
        var characters = Data()
        for record in records {
            characters.append(record.states.rawValue)
            characters.appendUInt16(record.characterId)
            characters.appendUInt16(record.depth)
            characters.append(0) // MATRIX: no scale, no rotate, 0-bit translate
            characters.append(0) // CXFORMWITHALPHA: no add, no multiply
        }
        characters.append(0) // CharacterEndFlag
        var body = Data()
        body.appendUInt16(characterId)
        body.append(trackAsMenu ? 1 : 0)
        body.appendUInt16(conditions.isEmpty ? 0 : UInt16(2 + characters.count))
        body.append(characters)
        for (index, condition) in conditions.enumerated() {
            let stream = SWFActionFixture.stream(condition.actions)
            let isLast = index == conditions.count - 1
            body.appendUInt16(isLast ? 0 : UInt16(4 + stream.count))
            body.append(condition.transitions)
            body.append(condition.keyByte)
            body.append(stream)
        }
        return SWFFixture.Tag(code: SWFButton.tagCode, body: body)
    }

    public static func scalingGridTag(characterId: UInt16, splitter: SWFRect) -> SWFFixture.Tag {
        var writer = SWFBitWriter()
        writer.appendUInt16LE(characterId)
        let values = [splitter.xMin, splitter.xMax, splitter.yMin, splitter.yMax]
        let width = values.map(SWFFixture.signedBitWidth).max() ?? 1
        writer.writeUB(UInt32(width), count: 5)
        for value in values {
            writer.writeSB(value, count: width)
        }
        return SWFFixture.Tag(code: SWFScalingGrid.tagCode, body: writer.bytes())
    }

    public static func fileAttributesTag(flags: UInt8) -> SWFFixture.Tag {
        SWFFixture.Tag(code: SWFFileAttributes.tagCode, body: Data([flags, 0, 0, 0]))
    }

    public static func metadataTag(_ text: String) -> SWFFixture.Tag {
        SWFFixture.Tag(code: SWFMetadata.tagCode, body: Data(text.utf8) + Data([0]))
    }
}
