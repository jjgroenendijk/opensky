// Developer > UI Lab > SWF runtime section (M8.3.3): runs the selected vanilla
// movie's ActionScript and shows what it did. Start brings the movie up, the
// tick buttons advance it, keys and pointer events are injected in movie stage
// pixels, and a named callback can be called across the `GameDelegate` bridge —
// the whole open / navigate / close sequence, without a CLI command.
//
// A sibling of SWFMovieSection under the same destination rather than more
// controls inside it: the static selector answers "what does frame 1 look
// like", this answers "what does the movie do", and the two have separate
// readout cadences. The milestone names `Developer > UI Lab` as the acceptance
// path, so it stays a hosted section there even though its control count sits
// at the promotion threshold in docs/tools/app-ui.md.
//
// Three readouts because the milestone gate names three things: movie state,
// invoke log, op tally. Their text is built by the device-free `SWFLabReadout`,
// and every control talks to the engine only through `SWFLabControlProviding`.

import AppKit

final class SWFRuntimeSection: PanelSectionViewController {
    /// Ticks the burst button applies. A vanilla menu's open and close
    /// animations are each about twenty frames long (measured on
    /// `tweenmenu.swf`: menu frame 0 to 10 to open, 10 to 19 to close), so a
    /// single-tick-only surface would be unusable for the acceptance sequence.
    static let burstTicks = 20

    /// Keys the section can inject, as ActionScript `Key` class codes. The
    /// navigation set is what a vanilla menu's `handleInput` acts on.
    static let keyChoices: [(title: String, code: Int)] = [
        ("Left", SWFKeyCode.left), ("Up", SWFKeyCode.up),
        ("Right", SWFKeyCode.right), ("Down", SWFKeyCode.down),
        ("Enter", SWFKeyCode.enter), ("Escape", SWFKeyCode.escape),
        ("Space", SWFKeyCode.space), ("Tab", SWFKeyCode.tab)
    ]

    weak var provider: (any SWFLabControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let startControl = NSButton(title: "Start", target: nil, action: nil)
    let tickControl = NSButton(title: "Tick", target: nil, action: nil)
    let burstControl = NSButton(
        title: "Tick x\(SWFRuntimeSection.burstTicks)", target: nil, action: nil
    )
    let stopControl = NSButton(title: "Stop", target: nil, action: nil)

    let keyControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let sendKeyControl = NSButton(title: "Send key", target: nil, action: nil)
    let pointerXControl = NSTextField(string: "0")
    let pointerYControl = NSTextField(string: "0")
    let pointerMoveControl = NSButton(title: "Move", target: nil, action: nil)
    let pointerClickControl = NSButton(title: "Click", target: nil, action: nil)

    /// Editable so any name can be called, and populated with the movie's own
    /// `GameDelegate.addCallBack` names so the usual ones need no typing.
    let callControl = NSComboBox()
    let callInvokeControl = NSButton(title: "Call", target: nil, action: nil)
    let clearLogControl = NSButton(title: "Clear log", target: nil, action: nil)

    private let stateLabel = PanelComponents.statsLabel(identifier: "SWFRuntimeStatsLabel")
    private let invokeLabel = PanelComponents.statsLabel(
        identifier: "SWFRuntimeInvokeStatsLabel"
    )
    private let tallyLabel = PanelComponents.statsLabel(identifier: "SWFRuntimeTallyStatsLabel")

    /// Callback names currently in the combo box, so the list is rebuilt only
    /// when the movie's own list changed and typing is never interrupted.
    private var callbackNames: [String] = []

    override var sectionTitle: String {
        "SWF runtime"
    }

    override var sectionIdentifier: String {
        "swfRuntime"
    }

    /// Current readout texts; the verification-surface tests read them directly.
    var stateReadout: String {
        stateLabel.stringValue
    }

    var invokeReadout: String {
        invokeLabel.stringValue
    }

    var tallyReadout: String {
        tallyLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "Runs the selected movie's ActionScript: Start executes every "
                    + "DoInitAction, then frame 1 and its DoAction. Ticks, keys, and "
                    + "pointer events are explicit — the layer reads no clock. Pointer "
                    + "coordinates are movie stage pixels."
            ),
            PanelComponents.buttonRow([startControl, tickControl, burstControl, stopControl]),
            PanelComponents.caption("Input"),
            PanelComponents.buttonRow([keyControl, sendKeyControl]),
            PanelComponents.labeledFieldRow(
                caption: "Pointer x", captionWidth: 70, field: pointerXControl
            ),
            PanelComponents.labeledFieldRow(
                caption: "Pointer y", captionWidth: 70, field: pointerYControl
            ),
            PanelComponents.buttonRow([pointerMoveControl, pointerClickControl]),
            PanelComponents.caption("Movie callback"),
            callControl,
            PanelComponents.buttonRow([callInvokeControl, clearLogControl]),
            stateLabel,
            invokeLabel,
            tallyLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.swfLabSnapshot
        startControl.isEnabled = snapshot?.selectedPath != nil
        let running = snapshot?.runtime != nil
        for control: NSControl in [
            tickControl, burstControl, stopControl, keyControl, sendKeyControl,
            pointerXControl, pointerYControl, pointerMoveControl, pointerClickControl,
            callControl, callInvokeControl, clearLogControl
        ] {
            control.isEnabled = running
        }
        reloadCallbacks(snapshot?.runtime?.callbackNames ?? [])
    }

    override func refreshReadout() {
        guard let provider else {
            stateLabel.stringValue = "SWF runtime unavailable."
            invokeLabel.stringValue = ""
            tallyLabel.stringValue = ""
            return
        }
        let snapshot = provider.swfLabSnapshot
        stateLabel.stringValue = SWFLabReadout.runtimeText(for: snapshot)
        invokeLabel.stringValue = SWFLabReadout.invokeText(for: snapshot)
        tallyLabel.stringValue = SWFLabReadout.tallyText(for: snapshot)
    }

    /// Rebuilds the callback list, preserving whatever the user typed. Only on
    /// a real change: rebuilding under the cursor would fight the editor.
    private func reloadCallbacks(_ names: [String]) {
        guard names != callbackNames else {
            return
        }
        callbackNames = names
        let typed = callControl.stringValue
        callControl.removeAllItems()
        callControl.addItems(withObjectValues: names)
        callControl.stringValue = typed
    }
}
