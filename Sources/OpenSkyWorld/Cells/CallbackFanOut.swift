// Ordered multicast for the engine callbacks `WorldSessionWiring` wires. A
// plain closure property would drop the first handler on a second assignment.
// No removal and no thread hand-off: every handler is wired once at setup and
// fires on the thread that drives `draw(in:)`.

import Foundation

/// Ordered multicast for one engine callback. With no handlers it does
/// nothing. A callback with several arguments uses a tuple `Value`.
public final class CallbackFanOut<Value> {
    private var handlers: [(Value) -> Void] = []

    /// How many handlers are registered. Tests assert on it; the engine does
    /// not branch on it.
    public var handlerCount: Int {
        handlers.count
    }

    /// Appends a handler. Registration order is delivery order.
    public func add(_ handler: @escaping (Value) -> Void) {
        handlers.append(handler)
    }

    /// Delivers `value` to every handler, in registration order.
    public func callAsFunction(_ value: Value) {
        for handler in handlers {
            handler(value)
        }
    }
}
