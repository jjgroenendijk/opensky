// Developer > UI Lab AS2 runtime readout coverage (M8.3.3). The three readouts
// the milestone gate names — movie state, invoke log, op tally — are pure
// functions of a value snapshot, so their exact wording is asserted here
// without AppKit, without a Metal device, and without a game install. The
// truncation cases matter most: a clipped list must still say how much it
// stopped showing.

@testable import opensky
import Testing

struct SWFLabRuntimeReadoutTests {
    private static func snapshot(
        selectedPath: String? = "interface\\tweenmenu.swf",
        runtime: SWFLabRuntimeSnapshot? = nil
    ) -> SWFLabControlSnapshot {
        SWFLabControlSnapshot(
            selectedPath: selectedPath,
            layerEnabled: true,
            loadError: nil,
            tally: nil,
            unresolvedFontNames: [],
            drawStats: SWFDrawStats(),
            installLoaded: true,
            runtime: runtime
        )
    }

    private static func entry(
        _ direction: SWFInvokeEntry.Direction,
        _ name: String,
        arguments: String = "",
        result: String = "undefined",
        isHandled: Bool = true
    ) -> SWFInvokeEntry {
        SWFInvokeEntry(
            direction: direction, name: name, arguments: arguments,
            result: result, isHandled: isHandled
        )
    }

    // MARK: Movie state

    @Test
    func runtimeTextSeparatesNoMovieFromNotStarted() {
        #expect(
            SWFLabReadout.runtimeText(for: Self.snapshot(selectedPath: nil))
                == "Runtime: no movie selected"
        )
        #expect(SWFLabReadout.runtimeText(for: Self.snapshot()).hasPrefix("Runtime: stopped"))
    }

    @Test
    func runtimeTextReportsStateNodesFocusInputAndDrops() {
        let runtime = SWFLabRuntimeSnapshot(
            isStarted: true, tickCount: 20, nodeCount: 39, rootChildCount: 2,
            currentFrame: 10, frameCount: 20, focusPath: "/Menu_mc/list",
            droppedInstantiations: 3, droppedFrameActions: 1, timerCount: 2,
            droppedTimers: 4, pointerEvents: 6, keyEvents: 5, lastKeyCode: 39
        )
        let text = SWFLabReadout.runtimeText(for: Self.snapshot(runtime: runtime))
        #expect(text == """
        Runtime: running · tick 20 · frame 10/20
        Nodes: 39 · root children 2 · timers 2
        Focus: /Menu_mc/list
        Input: pointer 6 · key 5 · last key 39
        Dropped: nodes 3 · frame actions 1 · timers 4
        """)
    }

    @Test
    func runtimeTextReportsAnUnfocusedTreeAsNone() {
        let text = SWFLabReadout.runtimeText(for: Self.snapshot(runtime: SWFLabRuntimeSnapshot()))
        #expect(text.contains("Focus: none"))
        #expect(text.contains("Runtime: loaded"))
        #expect(text.contains("frame -1/0"))
    }

    // MARK: Invoke log

    @Test
    func invokeTextReportsBothDirectionsAndMarksUnhandled() {
        var log = SWFInvokeLog()
        log.append(Self.entry(.engineToMovie, "StartOpenMenuAnim"))
        log.append(Self.entry(.movieToEngine, "HighlightMenu", arguments: "3"))
        log.append(Self.entry(.movieToEngine, "SaveGame", isHandled: false))
        let runtime = SWFLabRuntimeSnapshot(
            callbackNames: ["InitExtensions", "SetPlatform", "StartOpenMenuAnim"],
            invokeLog: log
        )
        #expect(SWFLabReadout.invokeText(for: Self.snapshot(runtime: runtime)) == """
        Invokes: 3 total · 1 unhandled · 0 dropped
        Callbacks: InitExtensions, SetPlatform, StartOpenMenuAnim
        Recent (3 of 3):
        engine->movie StartOpenMenuAnim() -> undefined
        movie->engine HighlightMenu(3) -> undefined
        movie->engine SaveGame() -> undefined [unhandled]
        """)
    }

    /// A truncated list must never look complete: the header keeps the totals
    /// and the drop count, and the body says how many of how many it shows.
    @Test
    func invokeTextNeverHidesDroppedOrClippedEntries() {
        var log = SWFInvokeLog(entryLimit: 4)
        for index in 0 ..< 10 {
            log.append(Self.entry(.movieToEngine, "Call\(index)"))
        }
        let text = SWFLabReadout.invokeText(
            for: Self.snapshot(runtime: SWFLabRuntimeSnapshot(invokeLog: log))
        )
        #expect(text.contains("Invokes: 10 total · 0 unhandled · 6 dropped"))
        #expect(text.contains("Recent (4 of 10):"))
        #expect(text.contains("movie->engine Call9() -> undefined"))
        #expect(!text.contains("Call5("))
    }

    @Test
    func invokeTextClipsALongCallbackList() {
        let runtime = SWFLabRuntimeSnapshot(
            callbackNames: ["A1", "B2", "C3", "D4", "E5"]
        )
        let text = SWFLabReadout.invokeText(for: Self.snapshot(runtime: runtime))
        #expect(text.contains("Callbacks: 5 (A1, B2, C3, …)"))
        #expect(text.contains("Recent: none"))
    }

    @Test
    func invokeTextReportsAnEmptyBridge() {
        let text = SWFLabReadout.invokeText(for: Self.snapshot(runtime: SWFLabRuntimeSnapshot()))
        #expect(text.contains("Invokes: 0 total · 0 unhandled · 0 dropped"))
        #expect(text.contains("Callbacks: none"))
        #expect(SWFLabReadout.invokeText(for: Self.snapshot()) == "Invokes: runtime not started")
    }

    // MARK: Op tally

    @Test
    func tallyTextReportsACleanRun() {
        var tally = AS2Tally()
        tally.noteBlock(actions: 41)
        tally.noteCall()
        #expect(SWFLabReadout.tallyText(for: Self.snapshot(runtime: SWFLabRuntimeSnapshot(
            tally: tally
        ))) == """
        Ops: 41 actions · 1 blocks · 1 calls
        Faults: 0 · underflows 0
        Unimplemented: none
        Missing: none
        Trace: none
        """)
        #expect(SWFLabReadout.tallyText(for: Self.snapshot()) == "Ops: runtime not started")
    }

    /// The tally is the milestone's risk-management mechanism, so faults and
    /// missing host APIs have to be named, not just counted.
    @Test
    func tallyTextRanksFaultKindsOpcodesAndMissingNames() {
        var tally = AS2Tally()
        tally.noteStackUnderflow()
        for _ in 0 ..< 3 {
            tally.note(fault: .callDepthExceeded(offset: 12))
        }
        tally.note(fault: .invalidJump(offset: 4, target: 900))
        tally.noteUnimplemented(opcode: 0x9F)
        tally.noteUnimplemented(opcode: 0x9F)
        tally.noteUnimplemented(opcode: 0xEE)
        for _ in 0 ..< 4 {
            tally.noteMissing("Map.MapMarker")
        }
        tally.noteMissing("addEventListener")
        let text = SWFLabReadout.tallyText(
            for: Self.snapshot(runtime: SWFLabRuntimeSnapshot(tally: tally))
        )
        #expect(text.contains("Faults: 4 (callDepthExceeded 3, invalidJump 1) · underflows 1"))
        // Named where the action table knows the opcode, hex where it does not.
        #expect(text.contains("Unimplemented: 3 (ActionGotoFrame2 2, 0xEE 1)"))
        #expect(text.contains("Missing: 5 (Map.MapMarker 4, addEventListener 1)"))
    }

    @Test
    func tallyTextShowsTheLastTraceMessage() {
        var trace = AS2TraceLog()
        trace.append("menu ready")
        trace.append("selection 3")
        let text = SWFLabReadout.tallyText(
            for: Self.snapshot(runtime: SWFLabRuntimeSnapshot(trace: trace))
        )
        #expect(text.contains("Trace: 2 · dropped 0 · last \"selection 3\""))
    }

    // MARK: Live runtime

    /// The snapshot is what the panel reads at 2 Hz, so it has to mirror a real
    /// runtime rather than a hand-built value. Synthetic movie, no install.
    @Test
    func snapshotMirrorsALiveRuntime() throws {
        let runtime = try SWFRuntimeFixture.started(tags: SWFRuntimeFixture.classMovieTags())
        runtime.advance()
        runtime.advance()
        runtime.handle(.keyDown(code: SWFKeyCode.right, ascii: 0))
        runtime.noteInvoke(
            SWFInvokeEntry(
                direction: .engineToMovie, name: "StartOpenMenuAnim",
                arguments: "", result: "undefined", isHandled: true
            )
        )

        let snapshot = SWFLabRuntimeSnapshot(runtime: runtime)
        #expect(snapshot.isStarted)
        #expect(snapshot.tickCount == 2)
        #expect(snapshot.nodeCount == runtime.nodeCount)
        #expect(snapshot.rootChildCount == runtime.root.childCount)
        #expect(snapshot.currentFrame == runtime.root.currentFrame)
        #expect(snapshot.keyEvents == 1)
        #expect(snapshot.lastKeyCode == SWFKeyCode.right)
        #expect(snapshot.invokeLog.total == 1)
        #expect(snapshot.tally == runtime.tally)
        #expect(snapshot == SWFLabRuntimeSnapshot(runtime: runtime))

        let text = SWFLabReadout.runtimeText(for: Self.snapshot(runtime: snapshot))
        #expect(text.contains("Runtime: running · tick 2"))
        #expect(text.contains("Nodes: \(runtime.nodeCount)"))
    }
}
