// Explicit multicast for the single-assignment engine callbacks wired in
// GameViewControllerStreaming (issue #171).
//
// Every engine seam started life as one optional closure assigned exactly
// once. As subsystems multiplied, several of them grew a second interested
// party, and a plain property makes the second assignment silently drop the
// first. This is the smallest thing that fixes that: an ordered list of
// handlers, nothing more. It is deliberately not an observer framework —
// there is no removal, no identity, and no thread hand-off, because every
// engine callback is wired once at setup and fired on the thread that drives
// `draw(in:)`.

import Foundation

/// Ordered multicast wrapper for one engine callback. Handlers run in
/// registration order; zero handlers is a no-op, which is the state every
/// seam is in until something subscribes.
///
/// Use a tuple `Value` for a callback that carries several arguments. Issue
/// #172 reuses this for `CellStreamer.onInteraction` when Papyrus subscribes
/// beside the world sound director.
final class CallbackFanOut<Value> {
    private var handlers: [(Value) -> Void] = []

    /// How many handlers are registered. Tests assert on it; the engine does
    /// not branch on it.
    var handlerCount: Int {
        handlers.count
    }

    /// Appends a handler. Registration order is delivery order.
    func add(_ handler: @escaping (Value) -> Void) {
        handlers.append(handler)
    }

    /// Delivers `value` to every handler, in registration order.
    func callAsFunction(_ value: Value) {
        for handler in handlers {
            handler(value)
        }
    }
}
