// The Controls page: one row per remappable action, then Reset. Accept on a
// row waits for the next key, and that key becomes the binding.

import Foundation
public import OpenSkyMenusInterface

nonisolated public enum ControlsPageAction: Equatable, Sendable {
    case rebind(GameInputAction, scanCode: UInt32)
    case resetAll
    case back
}

nonisolated public struct ControlsPageModel: Equatable, Sendable {
    static let resetTitle = "Reset to Defaults"

    private(set) var selectedIndex = 0
    /// True while the page waits for the key to bind.
    public private(set) var waitingForKey = false
    private(set) var confirmation: ConfirmationModel?

    public init() {}

    var rowCount: Int {
        InputBindings.slots.count + 1
    }

    public var selectedSlot: InputBindingSlot? {
        InputBindings.slots.indices.contains(selectedIndex)
            ? InputBindings.slots[selectedIndex] : nil
    }

    @discardableResult
    mutating func handle(_ event: MenuInputEvent) -> ControlsPageAction? {
        if var question = confirmation {
            let choice = question.handle(event)
            confirmation = choice == nil ? question : nil
            return choice == .chose(0) ? .resetAll : nil
        }
        if waitingForKey {
            if event == .button(.cancel) {
                waitingForKey = false
            }
            return nil
        }
        switch event {
        case .move(.up):
            selectedIndex = (selectedIndex + rowCount - 1) % rowCount
        case .move(.down):
            selectedIndex = (selectedIndex + 1) % rowCount
        case .button(.accept):
            if selectedSlot == nil {
                confirmation = ConfirmationModel(question: "Reset all controls?")
            } else {
                waitingForKey = true
            }
        case .button(.cancel):
            return .back
        default:
            break
        }
        return nil
    }

    /// The movie's Controls list picked the row of `event`; the next key binds it.
    mutating func beginRemap(event: String) {
        guard let index = InputBindings.slots.firstIndex(where: { $0.event == event }) else {
            return
        }
        selectedIndex = index
        confirmation = nil
        waitingForKey = true
    }

    /// The key pressed while waiting. Esc cancels instead of binding.
    public mutating func capture(scanCode: UInt32) -> ControlsPageAction? {
        guard waitingForKey, let slot = selectedSlot else { return nil }
        waitingForKey = false
        guard scanCode != 0x01 else { return nil }
        return .rebind(slot.action, scanCode: scanCode)
    }
}
