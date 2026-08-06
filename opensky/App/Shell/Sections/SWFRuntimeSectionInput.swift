// Control wiring + actions for Developer > UI Lab > SWF runtime (M8.3.3).
// Split from SWFRuntimeSection.swift so the section's type body stays inside
// the strict-lint limit; the accessibility identifiers set here are the
// UI-test API and are pinned literally in SWFRuntimeSectionTests.
//
// Every action is one engine call plus a resync. None of them can throw: the
// provider swallows a runtime failure into the readout, which is what keeps a
// malformed movie from taking a control action down with it.

import AppKit

extension SWFRuntimeSection {
    /// Wires target/action/identifier for every control. Called once from
    /// `makeContentViews()`.
    func configureControls() {
        configure(startControl, #selector(startPressed), "SWFRuntimeStartControl")
        configure(tickControl, #selector(tickPressed), "SWFRuntimeTickControl")
        configure(burstControl, #selector(burstPressed), "SWFRuntimeTickBurstControl")
        configure(stopControl, #selector(stopPressed), "SWFRuntimeStopControl")
        configure(sendKeyControl, #selector(sendKeyPressed), "SWFRuntimeSendKeyControl")
        configure(pointerMoveControl, #selector(pointerMovePressed), "SWFRuntimePointerMoveControl")
        configure(
            pointerClickControl, #selector(pointerClickPressed), "SWFRuntimePointerClickControl"
        )
        configure(callInvokeControl, #selector(callPressed), "SWFRuntimeCallInvokeControl")
        configure(clearLogControl, #selector(clearLogPressed), "SWFRuntimeClearLogControl")
        for choice in SWFRuntimeSection.keyChoices {
            keyControl.addItem(withTitle: choice.title)
        }
        PanelComponents.configurePopUp(
            keyControl, target: self, action: #selector(keyChanged),
            identifier: "SWFRuntimeKeyControl", width: 110
        )
        PanelComponents.configureComboBox(
            callControl, target: self, action: #selector(callPressed),
            identifier: "SWFRuntimeCallControl", width: PanelMetrics.contentWidth
        )
        configureField(pointerXControl, identifier: "SWFRuntimePointerXControl")
        configureField(pointerYControl, identifier: "SWFRuntimePointerYControl")
    }

    // MARK: Transport

    @objc func startPressed() {
        provider?.startSWFRuntime()
        syncControls()
        finishInteraction()
    }

    @objc func tickPressed() {
        provider?.advanceSWFRuntime(ticks: 1)
        syncControls()
        finishInteraction()
    }

    @objc func burstPressed() {
        provider?.advanceSWFRuntime(ticks: SWFRuntimeSection.burstTicks)
        syncControls()
        finishInteraction()
    }

    @objc func stopPressed() {
        provider?.stopSWFRuntime()
        syncControls()
        finishInteraction()
    }

    // MARK: Input

    /// A key press and its release, in one action. Both edges are injected
    /// because a movie tracks held keys through `Key.isDown`, but only the
    /// press is routed to `handleInput` — acting on both would move a menu
    /// selection twice per keystroke (see docs/engine/as2-runtime.md).
    @objc func sendKeyPressed() {
        let index = keyControl.indexOfSelectedItem
        guard SWFRuntimeSection.keyChoices.indices.contains(index) else {
            return
        }
        let code = SWFRuntimeSection.keyChoices[index].code
        provider?.sendSWFRuntimeInput(.keyDown(code: code, ascii: 0))
        provider?.sendSWFRuntimeInput(.keyUp(code: code))
        finishInteraction()
    }

    /// Selecting a key is not itself an event; the send button is.
    @objc func keyChanged() {
        finishInteraction()
    }

    @objc func pointerMovePressed() {
        provider?.sendSWFRuntimeInput(
            .pointerMoved(x: pointerXControl.doubleValue, y: pointerYControl.doubleValue)
        )
        finishInteraction()
    }

    /// Press and release at the same point — what a mouse click is, and what a
    /// CLIK button's `onPress`/`onRelease` pair expects.
    @objc func pointerClickPressed() {
        let pointX = pointerXControl.doubleValue
        let pointY = pointerYControl.doubleValue
        provider?.sendSWFRuntimeInput(.pointerPressed(x: pointX, y: pointY))
        provider?.sendSWFRuntimeInput(.pointerReleased(x: pointX, y: pointY))
        finishInteraction()
    }

    // MARK: Bridge

    @objc func callPressed() {
        provider?.callSWFRuntimeMovie(callControl.stringValue)
        syncControls()
        finishInteraction()
    }

    @objc func clearLogPressed() {
        provider?.clearSWFInvokeLog()
        finishInteraction()
    }

    // MARK: Wiring helpers

    private func configure(_ button: NSButton, _ action: Selector, _ identifier: String) {
        button.target = self
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    private func configureField(_ field: NSTextField, identifier: String) {
        field.alignment = .right
        field.font = PanelMetrics.monoDigitFont
        field.widthAnchor.constraint(equalToConstant: 105).isActive = true
        field.setAccessibilityIdentifier(identifier)
    }
}
