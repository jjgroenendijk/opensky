// Developer > UI Lab > SWF runtime section coverage (M8.3.3): every control
// drives the provider with the argument the acceptance sequence needs, the
// controls gate on whether a runtime is up, the callback list mirrors the
// movie's own registrations, and the three readouts render movie state, invoke
// log, and op tally instead of crashing.
//
// The accessibility ids are pinned literally — they are the UI-test API while
// make test-ui is blocked on this machine (docs/tools/app-ui.md).

import AppKit
@testable import opensky
import Testing

struct SWFRuntimeSectionTests {
    @MainActor
    private static func makeSection(
        runtime: SWFLabRuntimeSnapshot? = SWFLabRuntimeSnapshot(isStarted: true)
    ) -> (SWFRuntimeSection, FakeSWFLabProvider) {
        let section = SWFRuntimeSection()
        let provider = FakeSWFLabProvider()
        provider.snapshot = SWFLabControlSnapshot(
            selectedPath: "interface\\tweenmenu.swf",
            layerEnabled: true,
            loadError: nil,
            tally: nil,
            unresolvedFontNames: [],
            drawStats: SWFDrawStats(),
            installLoaded: true,
            runtime: runtime
        )
        section.provider = provider
        section.loadViewIfNeeded()
        return (section, provider)
    }

    @MainActor
    private static func press(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    @Test @MainActor
    func accessibilityIdentifiersAreStable() {
        let (section, _) = Self.makeSection()
        let expected: [(NSView, String)] = [
            (section.startControl, "SWFRuntimeStartControl"),
            (section.tickControl, "SWFRuntimeTickControl"),
            (section.burstControl, "SWFRuntimeTickBurstControl"),
            (section.stopControl, "SWFRuntimeStopControl"),
            (section.keyControl, "SWFRuntimeKeyControl"),
            (section.sendKeyControl, "SWFRuntimeSendKeyControl"),
            (section.pointerXControl, "SWFRuntimePointerXControl"),
            (section.pointerYControl, "SWFRuntimePointerYControl"),
            (section.pointerMoveControl, "SWFRuntimePointerMoveControl"),
            (section.pointerClickControl, "SWFRuntimePointerClickControl"),
            (section.callControl, "SWFRuntimeCallControl"),
            (section.callInvokeControl, "SWFRuntimeCallInvokeControl"),
            (section.clearLogControl, "SWFRuntimeClearLogControl")
        ]
        for (control, identifier) in expected {
            #expect(control.accessibilityIdentifier() == identifier)
        }
        #expect(section.sectionIdentifier == "swfRuntime")
        #expect(section.sectionTitle == "SWF runtime")
    }

    @Test @MainActor
    func controlsHaveVisibleFrames() {
        let (section, _) = Self.makeSection()
        section.view.frame = NSRect(x: 0, y: 0, width: 300, height: 700)
        section.view.layoutSubtreeIfNeeded()
        for control: NSView in [
            section.startControl, section.tickControl, section.burstControl,
            section.stopControl, section.keyControl, section.sendKeyControl,
            section.pointerXControl, section.pointerYControl, section.pointerMoveControl,
            section.pointerClickControl, section.callControl, section.callInvokeControl,
            section.clearLogControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0, "\(control) frame=\(control.frame)")
        }
    }

    // MARK: Transport

    @Test @MainActor
    func transportButtonsDriveTheProvider() {
        let (section, provider) = Self.makeSection()
        Self.press(section.startControl)
        Self.press(section.tickControl)
        Self.press(section.burstControl)
        Self.press(section.stopControl)
        #expect(provider.startCount == 1)
        #expect(provider.stopCount == 1)
        #expect(provider.advanceTicks == [1, SWFRuntimeSection.burstTicks])
    }

    /// A menu's open animation is about twenty frames, so the burst must cover
    /// it in one press or the acceptance sequence is unusable by hand.
    @Test @MainActor
    func burstCoversAMenuOpenAnimation() {
        #expect(SWFRuntimeSection.burstTicks == 20)
        let (section, _) = Self.makeSection()
        #expect(section.burstControl.title == "Tick x20")
    }

    // MARK: Input

    @Test @MainActor
    func sendKeyInjectsTheSelectedNavigationKeyDownThenUp() {
        let (section, provider) = Self.makeSection()
        let index = SWFRuntimeSection.keyChoices.firstIndex { $0.title == "Right" } ?? 0
        section.keyControl.selectItem(at: index)
        #expect(section.keyControl.titleOfSelectedItem == "Right")
        Self.press(section.sendKeyControl)
        #expect(provider.inputEvents == [
            .keyDown(code: SWFKeyCode.right, ascii: 0), .keyUp(code: SWFKeyCode.right)
        ])
    }

    @Test @MainActor
    func everyNavigationKeyIsReachable() {
        let (section, _) = Self.makeSection()
        let titles = SWFRuntimeSection.keyChoices.map(\.title)
        #expect(section.keyControl.itemTitles == titles)
        for expected in ["Left", "Up", "Right", "Down", "Enter", "Escape"] {
            #expect(titles.contains(expected))
        }
    }

    @Test @MainActor
    func pointerButtonsInjectStagePixels() {
        let (section, provider) = Self.makeSection()
        section.pointerXControl.stringValue = "120.5"
        section.pointerYControl.stringValue = "64"
        Self.press(section.pointerMoveControl)
        Self.press(section.pointerClickControl)
        #expect(provider.inputEvents == [
            .pointerMoved(x: 120.5, y: 64),
            .pointerPressed(x: 120.5, y: 64),
            .pointerReleased(x: 120.5, y: 64)
        ])
    }

    // MARK: Bridge

    @Test @MainActor
    func callButtonInvokesTheNamedCallback() {
        let (section, provider) = Self.makeSection()
        section.callControl.stringValue = "StartOpenMenuAnim"
        Self.press(section.callInvokeControl)
        Self.press(section.clearLogControl)
        #expect(provider.calledMovieNames == ["StartOpenMenuAnim"])
        #expect(provider.clearLogCount == 1)
    }

    /// The movie's own `GameDelegate.addCallBack` names populate the combo box,
    /// so the acceptance sequence needs no typing — but the box stays editable
    /// for a movie that ships no delegate.
    @Test @MainActor
    func callbackListMirrorsTheMovieAndKeepsTypedText() {
        let (section, provider) = Self.makeSection()
        #expect(section.callControl.numberOfItems == 0)
        section.callControl.stringValue = "Typed"
        provider.setRuntime(
            SWFLabRuntimeSnapshot(
                isStarted: true,
                callbackNames: ["InitExtensions", "SetPlatform", "StartOpenMenuAnim"]
            )
        )
        section.syncControls()
        #expect(
            section.callControl.objectValues as? [String]
                == ["InitExtensions", "SetPlatform", "StartOpenMenuAnim"]
        )
        #expect(section.callControl.stringValue == "Typed")
        #expect(section.callControl.isEditable)
    }

    // MARK: Gating

    @Test @MainActor
    func controlsGateOnTheRuntimeBeingUp() {
        let (section, _) = Self.makeSection(runtime: nil)
        #expect(section.startControl.isEnabled)
        for control: NSControl in [
            section.tickControl, section.burstControl, section.stopControl,
            section.keyControl, section.sendKeyControl, section.pointerMoveControl,
            section.pointerClickControl, section.callControl, section.callInvokeControl,
            section.clearLogControl
        ] {
            #expect(!control.isEnabled, "\(control) should be disabled without a runtime")
        }
    }

    @Test @MainActor
    func startDisablesWithoutASelectedMovie() {
        let (section, provider) = Self.makeSection(runtime: nil)
        provider.snapshot = SWFLabControlSnapshot(
            selectedPath: nil, layerEnabled: true, loadError: nil, tally: nil,
            unresolvedFontNames: [], drawStats: SWFDrawStats(), installLoaded: true,
            runtime: nil
        )
        section.syncControls()
        #expect(!section.startControl.isEnabled)
    }

    // MARK: Readouts

    @Test @MainActor
    func readoutsRenderStateInvokeAndTally() {
        let (section, provider) = Self.makeSection()
        var log = SWFInvokeLog()
        log.append(
            SWFInvokeEntry(
                direction: .movieToEngine, name: "HighlightMenu", arguments: "3",
                result: "undefined", isHandled: true
            )
        )
        var tally = AS2Tally()
        tally.noteBlock(actions: 96)
        provider.setRuntime(
            SWFLabRuntimeSnapshot(
                isStarted: true, tickCount: 20, nodeCount: 39, rootChildCount: 2,
                currentFrame: 10, frameCount: 20, callbackNames: ["StartOpenMenuAnim"],
                invokeLog: log, tally: tally
            )
        )
        section.refreshReadout()
        #expect(section.stateReadout.contains("Runtime: running · tick 20 · frame 10/20"))
        #expect(section.stateReadout.contains("Nodes: 39"))
        #expect(section.invokeReadout.contains("movie->engine HighlightMenu(3) -> undefined"))
        #expect(section.invokeReadout.contains("Callbacks: StartOpenMenuAnim"))
        #expect(section.tallyReadout.contains("Ops: 96 actions · 1 blocks · 0 calls"))
        #expect(section.tallyReadout.contains("Faults: 0"))
    }

    @Test @MainActor
    func readoutsDegradeWithoutAProvider() {
        let section = SWFRuntimeSection()
        section.loadViewIfNeeded()
        section.refreshReadout()
        #expect(section.stateReadout == "SWF runtime unavailable.")
        #expect(section.invokeReadout.isEmpty)
        #expect(section.tallyReadout.isEmpty)
    }
}
