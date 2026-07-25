// Developer > UI Lab SWF runtime bridge (M8.3.3): the app-facing half of the
// AS2 runtime. Satellite of GameViewControllerSWFLab.swift, which owns the
// static movie selector; this file owns start / tick / input / call / stop over
// the 8.3.2 renderer API (`Renderer.startSWFRuntime`, `advanceSWFRuntime`,
// `sendSWFInput`, `callSWFMovie`, `stopSWFRuntime`).
//
// Every entry point is a control action, so none of them throws. The renderer
// calls can throw on a GPU allocation or a ring regrow; that message lands in
// `swfLab.loadError` and shows up in the panel readout, exactly as a decode
// failure does. A running movie must not be able to take the app down
// (AGENTS.md "Reverse-engineering discipline").
//
// Nothing here reads a clock. A tick happens because the user pressed a tick
// button, which is the determinism contract in docs/rendering/ui.md restated at
// the app surface.

import AppKit

extension GameViewController {
    func startSWFRuntime() {
        guard let renderer else {
            swfLab.loadError = Self.noRendererMessage
            return
        }
        do {
            guard try renderer.startSWFRuntime() != nil else {
                swfLab.loadError = "Select a movie before starting the runtime."
                return
            }
            swfLab.loadError = nil
        } catch {
            swfLab.loadError = Self.runtimeMessage("start", error)
        }
    }

    /// Applies `ticks` ticks one at a time, so a fault on tick 3 still leaves
    /// the first two applied and reported rather than rolling the movie back.
    func advanceSWFRuntime(ticks: Int) {
        guard let renderer = startedRenderer() else {
            return
        }
        do {
            for _ in 0 ..< max(1, ticks) {
                try renderer.advanceSWFRuntime()
            }
        } catch {
            swfLab.loadError = Self.runtimeMessage("advance", error)
        }
    }

    func stopSWFRuntime() {
        guard let renderer else {
            swfLab.loadError = Self.noRendererMessage
            return
        }
        do {
            try renderer.stopSWFRuntime()
            swfLab.loadError = nil
        } catch {
            swfLab.loadError = Self.runtimeMessage("stop", error)
        }
    }

    func sendSWFRuntimeInput(_ event: SWFInputEvent) {
        guard let renderer = startedRenderer() else {
            return
        }
        do {
            try renderer.sendSWFInput(event)
        } catch {
            swfLab.loadError = Self.runtimeMessage("input", error)
        }
    }

    func callSWFRuntimeMovie(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            swfLab.loadError = "Enter a callback name to call."
            return
        }
        guard let renderer = startedRenderer() else {
            return
        }
        do {
            try renderer.callSWFMovie(trimmed)
        } catch {
            swfLab.loadError = Self.runtimeMessage("call", error)
        }
    }

    func clearSWFInvokeLog() {
        renderer?.swfRuntime?.clearInvokeLog()
    }

    /// The renderer, but only while a runtime is up. Reports the reason in the
    /// readout otherwise, so a button press is never silently ignored.
    private func startedRenderer() -> Renderer? {
        guard let renderer else {
            swfLab.loadError = Self.noRendererMessage
            return nil
        }
        guard renderer.swfRuntime != nil else {
            swfLab.loadError = "Runtime not started."
            return nil
        }
        return renderer
    }

    private static let noRendererMessage = "No renderer: Metal 4 device unavailable."

    private static func runtimeMessage(_ stage: String, _ error: Error) -> String {
        "SWF runtime \(stage) failed: \(String(describing: error))"
    }
}
