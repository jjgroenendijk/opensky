// Timeline model for the main movie and every DefineSprite (39): each frame's
// control tags and action blocks, plus the resolved frame-1 display list.
// `SWFMovieTally` counts only up to the first ShowFrame (SWF spec v19, ch. 3,
// 5, 13).

import Foundation

/// One display-list mutation inside a frame, in tag order.
nonisolated public enum SWFTimelineStep: Equatable, Sendable {
    case place(SWFPlacement)
    case remove(SWFRemoval)

    /// The CLIPACTIONS handlers this step attaches to a placed sprite, if any.
    public var clipActionBlocks: [SWFActionBlock] {
        guard case let .place(placement) = self, let clip = placement.clipActions else {
            return []
        }
        return clip.records.map(\.actions)
    }

    /// CLIPACTIONS framing problems recorded on this step.
    public var clipActionWarnings: Int {
        guard case let .place(placement) = self, let clip = placement.clipActions else {
            return 0
        }
        return clip.warnings.count
    }
}

/// One frame: the control tags that execute before its ShowFrame, the
/// DoAction (12) blocks that run with it, and the FrameLabel (43) naming it.
nonisolated public struct SWFTimelineFrame: Equatable, Sendable {
    public let steps: [SWFTimelineStep]
    public let actions: [SWFActionBlock]
    /// FrameLabel (43) attached to this frame, or nil when it has none.
    public let label: String?

    public init(steps: [SWFTimelineStep], actions: [SWFActionBlock], label: String? = nil) {
        self.steps = steps
        self.actions = actions
        self.label = label
    }
}

/// A decoded timeline: every frame, plus the display list and tag counters
/// frame 1 resolves to.
nonisolated public struct SWFTimeline: Equatable, Sendable {
    /// Frames in playback order. A trailing run of tags without a closing
    /// ShowFrame still forms a frame, matching how a player would publish it.
    public let frames: [SWFTimelineFrame]
    /// Display list after frame 1, depth-ascending (the paint order).
    public let frame1: [SWFPlacedObject]
    /// Display-list counters for frame 1 only.
    public let tally: SWFMovieTally

    /// Zero-based index of the frame carrying `label`. Matched exactly first,
    /// then case-insensitively: ActionScript path and label matching is
    /// case-insensitive below SWF 7, and authors mix casing either way.
    public func frameIndex(forLabel label: String) -> Int? {
        if let exact = frames.firstIndex(where: { $0.label == label }) {
            return exact
        }
        let folded = label.lowercased()
        return frames.firstIndex { $0.label?.lowercased() == folded }
    }

    /// Every label in frame order, for reporting.
    public var frameLabels: [String] {
        frames.compactMap(\.label)
    }

    /// Every action stream this timeline carries, frame by frame: the frame's
    /// DoAction blocks first, then the CLIPACTIONS handlers its placements
    /// attach.
    public var actionBlocks: [SWFActionBlock] {
        frames.flatMap { frame in
            frame.actions + frame.steps.flatMap(\.clipActionBlocks)
        }
    }

    /// Action-side counters over every frame of this timeline.
    public var actionTally: SWFMovieTally {
        var tally = SWFMovieTally()
        for frame in frames {
            for block in frame.actions {
                tally.record(actions: block)
            }
            for step in frame.steps {
                tally.actionWarnings += step.clipActionWarnings
                for block in step.clipActionBlocks {
                    tally.record(actions: block)
                }
            }
        }
        return tally
    }
}

/// Walks a control-tag stream once and splits it into frames. The main movie
/// and every sprite body run through this, so a later runtime steps either the
/// same way.
nonisolated public struct SWFTimelineDecoder: Sendable {
    /// The movie's SWF version — CLIPEVENTFLAGS width depends on it.
    public let version: UInt8
    /// SetBackgroundColor (9) seen in frame 1; nil when the stream sets none.
    public private(set) var backgroundColor: SWFColor?
    private var builder = SWFDisplayListBuilder()
    private var frozen = false
    private var frames: [SWFTimelineFrame] = []
    private var steps: [SWFTimelineStep] = []
    private var actions: [SWFActionBlock] = []
    private var label: String?
    private var malformedTags = 0

    public init(version: UInt8) {
        self.version = version
    }

    /// Executes one tag. Definition tags are ignored here; the movie decoder
    /// routes those into the character dictionary.
    public mutating func accept(_ tag: SWFTag) {
        switch tag.code {
        case SWFDisplayListParser.placeObjectCode,
             SWFDisplayListParser.placeObject2Code,
             SWFDisplayListParser.placeObject3Code:
            acceptPlacement(tag)
        case SWFDisplayListParser.removeObjectCode,
             SWFDisplayListParser.removeObject2Code:
            acceptRemoval(tag)
        case SWFDisplayListParser.setBackgroundColorCode:
            if
                !frozen,
                let color = parsed({ try SWFDisplayListParser.parseBackgroundColor(tag: tag) })
            {
                backgroundColor = color
            }
        case SWFDisplayListParser.showFrameCode:
            if !frozen {
                builder.noteShowFrame()
            }
            closeFrame()
            frozen = true
        case SWFActionParser.doActionCode:
            if let block = parsed({ try SWFActionParser.parseDoAction(tag: tag) }) {
                actions.append(block)
            }
        case SWFFrameLabel.tagCode:
            // A malformed label loses the name, never the frame.
            if let decoded = parsed({ try SWFFrameLabel.parse(tag: tag) }), !decoded.name.isEmpty {
                label = decoded.name
            }
        default:
            break
        }
    }

    /// Closes any pending frame and resolves frame 1.
    public mutating func finish() -> SWFTimeline {
        if !steps.isEmpty || !actions.isEmpty || label != nil {
            closeFrame()
        }
        var tally = builder.tally
        tally.malformedTags = malformedTags
        return SWFTimeline(frames: frames, frame1: builder.placements, tally: tally)
    }

    private mutating func parsed<Value>(_ parse: () throws -> Value) -> Value? {
        do {
            return try parse()
        } catch {
            malformedTags += 1
            return nil
        }
    }

    private mutating func acceptPlacement(_ tag: SWFTag) {
        if !frozen {
            notePlaceTally(tag.code)
        }
        let version = version
        guard
            let placement = parsed({
                try SWFDisplayListParser.parsePlacement(tag: tag, version: version)
            })
        else {
            if !frozen {
                builder.noteDanglingPlacement()
            }
            return
        }
        steps.append(.place(placement))
        if !frozen {
            builder.apply(placement)
        }
    }

    private mutating func acceptRemoval(_ tag: SWFTag) {
        guard let removal = parsed({ try SWFDisplayListParser.parseRemoval(tag: tag) }) else {
            return
        }
        steps.append(.remove(removal))
        if !frozen {
            builder.remove(removal)
        }
    }

    private mutating func closeFrame() {
        frames.append(SWFTimelineFrame(steps: steps, actions: actions, label: label))
        steps = []
        actions = []
        label = nil
    }

    private mutating func notePlaceTally(_ code: UInt16) {
        switch code {
        case SWFDisplayListParser.placeObjectCode: builder.notePlaceObject(version: 1)
        case SWFDisplayListParser.placeObject2Code: builder.notePlaceObject(version: 2)
        default: builder.notePlaceObject(version: 3)
        }
    }
}

nonisolated extension SWFMovieTally {
    /// Accumulates one parsed action stream into the action-side counters.
    public mutating func record(actions block: SWFActionBlock) {
        actionBlocks += 1
        actionRecords += block.records.count
        actionWarnings += block.warnings.count
        for record in block.records {
            if !SWFActionName.isKnown(record.code) {
                unknownActionOpcodes += 1
            } else if record.carriesOperands, record.operands == .none {
                undecodedActionOpcodes += 1
            }
        }
    }
}
