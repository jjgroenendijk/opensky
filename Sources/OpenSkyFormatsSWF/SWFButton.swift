// DefineButton2 (34): a button character with per-state display records and
// actions keyed on state transitions. The runtime runs it as a stopped clip with
// one frame per state. Layout: docs/formats/swf-display-list.md, "Buttons".

import Foundation
import OpenSkyFormatsCore

/// The states one BUTTONRECORD appears in.
nonisolated public struct SWFButtonStates: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let up = SWFButtonStates(rawValue: 1 << 0)
    public static let over = SWFButtonStates(rawValue: 1 << 1)
    public static let down = SWFButtonStates(rawValue: 1 << 2)
    public static let hitTest = SWFButtonStates(rawValue: 1 << 3)
}

/// One BUTTONRECORD.
nonisolated public struct SWFButtonRecord: Equatable, Sendable {
    public let states: SWFButtonStates
    public let characterId: UInt16
    public let depth: UInt16
    public let matrix: SWFMatrix
    public let colorTransform: SWFColorTransform
}

/// One BUTTONCONDACTION: the transitions that run it, and its action stream.
nonisolated public struct SWFButtonCondition: Equatable, Sendable {
    /// The transition flags as clip events (`press`, `release`, `rollOver`, ...).
    public let events: SWFClipEventFlags
    /// `CondKeyPress`, or nil when the condition traps no key.
    public let keyCode: UInt8?
    public let actions: SWFActionBlock
}

/// A decoded DefineButton2 (34) tag.
nonisolated public struct SWFButton: Equatable, Sendable {
    public static let tagCode: UInt16 = 34
    /// The frame labels of the synthesized state timeline, in frame order.
    public static let stateLabels = ["_up", "_over", "_down"]

    public let characterId: UInt16
    public let trackAsMenu: Bool
    public let records: [SWFButtonRecord]
    public let conditions: [SWFButtonCondition]

    public static func parse(tag: SWFTag) throws -> SWFButton {
        guard tag.code == tagCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var bits = SWFBitReader(tag.body)
        let characterId = try bits.readAlignedUInt16()
        let flags = try bits.readAlignedUInt8()
        let actionOffset = try Int(bits.readAlignedUInt16())
        var records: [SWFButtonRecord] = []
        while let record = try readRecord(&bits) {
            records.append(record)
        }
        // ActionOffset counts from its own field, which starts at byte 3.
        let conditions = actionOffset == 0 ? [] : readConditions(tag.body, from: 3 + actionOffset)
        return SWFButton(
            characterId: characterId,
            trackAsMenu: flags & 0x01 != 0,
            records: records,
            conditions: conditions
        )
    }

    /// One frame per state: each removes the previous state's records and
    /// places its own, so a jump replayed from frame 1 lands on that state.
    public var stateTimeline: SWFTimeline {
        let states: [SWFButtonStates] = [.up, .over, .down]
        var frames: [SWFTimelineFrame] = []
        var previous: [SWFButtonRecord] = []
        for (state, label) in zip(states, Self.stateLabels) {
            let shown = records.filter { $0.states.contains(state) }
            let removals = previous.map {
                SWFTimelineStep.remove(SWFRemoval(depth: $0.depth, characterId: nil))
            }
            let places = shown.map { SWFTimelineStep.place($0.placement) }
            frames.append(SWFTimelineFrame(steps: removals + places, actions: [], label: label))
            previous = shown
        }
        var builder = SWFDisplayListBuilder()
        for record in records where record.states.contains(.up) {
            builder.apply(record.placement)
        }
        return SWFTimeline(frames: frames, frame1: builder.placements, tally: builder.tally)
    }

    /// The conditions as CLIPACTIONS, so the runtime's clip event path runs them.
    public var clipActions: SWFClipActions? {
        guard !conditions.isEmpty else { return nil }
        let records = conditions.map {
            SWFClipActionRecord(events: $0.events, keyCode: $0.keyCode, actions: $0.actions)
        }
        let all = conditions.reduce(SWFClipEventFlags(rawValue: 0)) { $0.union($1.events) }
        return SWFClipActions(allEvents: all, records: records, warnings: [])
    }

    /// BUTTONRECORD, or nil at `CharacterEndFlag`. Flag byte MSB -> LSB: two
    /// reserved bits, HasBlendMode, HasFilterList, HitTest, Down, Over, Up.
    private static func readRecord(_ bits: inout SWFBitReader) throws -> SWFButtonRecord? {
        let flags = try bits.readAlignedUInt8()
        guard flags != 0 else { return nil }
        let characterId = try bits.readAlignedUInt16()
        let depth = try bits.readAlignedUInt16()
        let matrix = try SWFShapeParser.parseMatrix(&bits)
        let colorTransform = try SWFColorTransform.parse(&bits, hasAlpha: true)
        if flags & 0x10 != 0 {
            _ = try SWFDisplayListParser.skipFilterList(&bits)
        }
        if flags & 0x20 != 0 {
            _ = try bits.readAlignedUInt8()
        }
        return SWFButtonRecord(
            states: SWFButtonStates(rawValue: flags & 0x0F),
            characterId: characterId,
            depth: depth,
            matrix: matrix,
            colorTransform: colorTransform
        )
    }

    /// BUTTONCONDACTION list. Each starts with `CondActionSize` (0 on the last),
    /// then two flag bytes and the action stream. A bad entry ends the list; the
    /// button keeps the conditions read so far.
    private static func readConditions(_ body: Data, from offset: Int) -> [SWFButtonCondition] {
        var conditions: [SWFButtonCondition] = []
        var start = offset
        while start + 4 <= body.count {
            var reader = BinaryReader(body)
            reader.skip(start)
            guard
                let size = try? Int(reader.readUInt16()),
                let transitions = try? reader.readUInt8(),
                let keyByte = try? reader.readUInt8()
            else { break }
            let end = size == 0 ? body.count : start + size
            guard end > start + 4, end <= body.count else { break }
            let streamStart = body.startIndex + start + 4
            let stream = body.subdata(in: streamStart ..< body.startIndex + end)
            let actions = SWFActionParser.parse(stream)
            let key = keyByte >> 1
            conditions.append(SWFButtonCondition(
                events: events(transitions: transitions, keyByte: keyByte),
                keyCode: key == 0 ? nil : key,
                actions: actions
            ))
            guard size != 0 else { break }
            start = end
        }
        return conditions
    }

    /// The transition flags as clip events. First byte MSB -> LSB: IdleToOverDown,
    /// OutDownToIdle, OutDownToOverDown, OverDownToOutDown, OverDownToOverUp,
    /// OverUpToOverDown, OverUpToIdle, IdleToOverUp. Second byte: CondKeyPress
    /// in the top 7 bits, OverDownToIdle in the lowest.
    static func events(transitions: UInt8, keyByte: UInt8) -> SWFClipEventFlags {
        let table: [(UInt8, SWFClipEventFlags)] = [
            (0x80, .dragOver), (0x40, .releaseOutside), (0x20, .dragOver), (0x10, .dragOut),
            (0x08, .release), (0x04, .press), (0x02, .rollOut), (0x01, .rollOver)
        ]
        var events = SWFClipEventFlags(rawValue: 0)
        for (bit, event) in table where transitions & bit != 0 {
            events.formUnion(event)
        }
        if keyByte & 0x01 != 0 {
            events.formUnion(.dragOut)
        }
        if keyByte >> 1 != 0 {
            events.formUnion(.keyPress)
        }
        return events
    }
}

nonisolated extension SWFButtonRecord {
    var placement: SWFPlacement {
        var placement = SWFPlacement()
        placement.depth = depth
        placement.characterId = characterId
        placement.matrix = matrix
        placement.colorTransform = colorTransform
        return placement
    }
}
