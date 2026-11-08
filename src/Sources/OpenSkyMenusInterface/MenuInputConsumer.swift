import OpenSkyFormatsCore

/// Implemented by the menu layer (none yet) to receive routed input.
public protocol MenuInputConsumer: AnyObject {
    func handleMenuInput(_ event: MenuInputEvent)
    func handleMenuPointer(_ event: MenuPointerEvent)
}

extension MenuInputConsumer {
    /// A menu that does not hit test takes a press as its accept button.
    public func handleMenuPointer(_ event: MenuPointerEvent) {
        if event.phase == .pressed {
            handleMenuInput(.button(.accept))
        }
    }
}
