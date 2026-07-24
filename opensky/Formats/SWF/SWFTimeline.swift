// Timeline model shared by the main movie and every DefineSprite (39): the
// control tags and action blocks of each frame, plus the resolved frame-1
// display list. Milestone 8.2.4 kept only frame 1 and threw the rest away;
// 8.3.1 retains every frame so a later runtime can step a timeline
// (`gotoAndStop`, `play`) and run the DoAction blocks attached to each frame.
//
// The frame-1 display list and every counter in `SWFMovieTally` are still built
// exactly as before — from the tags up to and including the first ShowFrame —
// so retaining the later frames changes no existing number.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 3 "The
// display list" (pp. 33-51) for the control tags, chapter 5 "Actions" (p. 63)
// for DoAction, and chapter 13 "Sprites and movie clips" (p. 201) for
// DefineSprite's nested tag stream.

import Foundation

/// One display-list mutation inside a frame, in tag order.
nonisolated enum SWFTimelineStep: Equatable {
    case place(SWFPlacement)
    case remove(SWFRemoval)

    /// The CLIPACTIONS handlers this step attaches to a placed sprite, if any.
    var clipActionBlocks: [SWFActionBlock] {
        guard case let .place(placement) = self, let clip = placement.clipActions else {
            return []
        }
        return clip.records.map(\.actions)
    }

    /// CLIPACTIONS framing problems recorded on this step.
    var clipActionWarnings: Int {
        guard case let .place(placement) = self, let clip = placement.clipActions else {
            return 0
        }
        return clip.warnings.count
    }
}

/// One frame: the control tags that execute before its ShowFrame and the
/// DoAction (12) blocks that run with it.
nonisolated struct SWFTimelineFrame: Equatable {
    let steps: [SWFTimelineStep]
    let actions: [SWFActionBlock]
}

/// A decoded timeline: every frame, plus the display list and tag counters
/// frame 1 resolves to.
nonisolated struct SWFTimeline: Equatable {
    /// Frames in playback order. A trailing run of tags without a closing
    /// ShowFrame still forms a frame, matching how a player would publish it.
    let frames: [SWFTimelineFrame]
    /// Display list after frame 1, depth-ascending (the paint order).
    let frame1: [SWFPlacedObject]
    /// Display-list counters for frame 1 only.
    let tally: SWFMovieTally

    static let empty = SWFTimeline(frames: [], frame1: [], tally: SWFMovieTally())

    /// Every action stream this timeline carries, frame by frame: the frame's
    /// DoAction blocks first, then the CLIPACTIONS handlers its placements
    /// attach.
    var actionBlocks: [SWFActionBlock] {
        frames.flatMap { frame in
            frame.actions + frame.steps.flatMap(\.clipActionBlocks)
        }
    }

    /// Action-side counters over every frame of this timeline.
    var actionTally: SWFMovieTally {
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
nonisolated struct SWFTimelineDecoder {
    /// The movie's SWF version — CLIPEVENTFLAGS width depends on it.
    let version: UInt8
    /// SetBackgroundColor (9) seen in frame 1; nil when the stream sets none.
    private(set) var backgroundColor: SWFColor?
    private var builder = SWFDisplayListBuilder()
    private var frozen = false
    private var frames: [SWFTimelineFrame] = []
    private var steps: [SWFTimelineStep] = []
    private var actions: [SWFActionBlock] = []

    init(version: UInt8) {
        self.version = version
    }

    /// Executes one tag. Definition tags are ignored here; the movie decoder
    /// routes those into the character dictionary.
    mutating func accept(_ tag: SWFTag) {
        switch tag.code {
        case SWFDisplayListParser.placeObjectCode,
             SWFDisplayListParser.placeObject2Code,
             SWFDisplayListParser.placeObject3Code:
            acceptPlacement(tag)
        case SWFDisplayListParser.removeObjectCode,
             SWFDisplayListParser.removeObject2Code:
            acceptRemoval(tag)
        case SWFDisplayListParser.setBackgroundColorCode:
            if !frozen, let color = try? SWFDisplayListParser.parseBackgroundColor(tag: tag) {
                backgroundColor = color
            }
        case SWFDisplayListParser.showFrameCode:
            if !frozen {
                builder.noteShowFrame()
            }
            closeFrame()
            frozen = true
        case SWFActionParser.doActionCode:
            if let block = try? SWFActionParser.parseDoAction(tag: tag) {
                actions.append(block)
            }
        default:
            break
        }
    }

    /// Closes any pending frame and resolves frame 1.
    mutating func finish() -> SWFTimeline {
        if !steps.isEmpty || !actions.isEmpty {
            closeFrame()
        }
        return SWFTimeline(frames: frames, frame1: builder.placements, tally: builder.tally)
    }

    private mutating func acceptPlacement(_ tag: SWFTag) {
        if !frozen {
            notePlaceTally(tag.code)
        }
        guard
            let placement = try? SWFDisplayListParser.parsePlacement(tag: tag, version: version)
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
        guard let removal = try? SWFDisplayListParser.parseRemoval(tag: tag) else {
            return
        }
        steps.append(.remove(removal))
        if !frozen {
            builder.remove(removal)
        }
    }

    private mutating func closeFrame() {
        frames.append(SWFTimelineFrame(steps: steps, actions: actions))
        steps = []
        actions = []
    }

    private mutating func notePlaceTally(_ code: UInt16) {
        switch code {
        case SWFDisplayListParser.placeObjectCode: builder.notePlaceObject(version: 1)
        case SWFDisplayListParser.placeObject2Code: builder.notePlaceObject(version: 2)
        default: builder.notePlaceObject(version: 3)
        }
    }
}

extension SWFMovieTally {
    /// Accumulates one parsed action stream into the action-side counters.
    mutating func record(actions block: SWFActionBlock) {
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
