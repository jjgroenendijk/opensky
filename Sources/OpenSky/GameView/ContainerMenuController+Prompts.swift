// The container and barter menu's two prompts: the count slider for a stack of more
// than five, and the confirm a sale opens when the merchant has too little gold
// (`sNotEnoughVendorGold`). See docs/engine/barter.md.

import OpenSkyMenus

extension ContainerMenuController {
    /// Left and right move by one, up and down by ten. Accept moves the count or
    /// takes the merchant's gold; cancel moves nothing.
    func routePrompt(_ event: MenuInputEvent) {
        if let sale = pendingSale {
            routeSaleConfirm(event, sale: sale)
        } else {
            routeQuantity(event)
        }
    }

    private func routeSaleConfirm(
        _ event: MenuInputEvent, sale: (entry: InventoryMenuEntry, count: Int32)
    ) {
        switch event {
        case .button(.accept):
            pendingSale = nil
            move(sale.entry, count: sale.count, acceptingLess: true)
        case .button(.cancel):
            pendingSale = nil
            noteAction("Kept \(sale.entry.name).")
        default:
            return
        }
    }

    private func routeQuantity(_ event: MenuInputEvent) {
        switch event {
        case .button(.accept), .button(.xButton):
            guard let prompt = quantity else { return }
            quantity = nil
            guard let entry = model.selectedEntry, entry.item == prompt.item else {
                noteAction("The row changed; moved nothing.")
                return
            }
            move(entry, count: prompt.value)
        case .button(.cancel):
            quantity = nil
            noteAction("Moved nothing.")
        case let .move(direction):
            let step: Int32 = switch direction {
            case .left: -1
            case .right: 1
            case .down: -10
            case .up: 10
            }
            quantity?.adjust(by: step)
            if let text = quantity?.text {
                noteAction(text)
            }
        case .button(.yButton), .pointer, .release:
            return
        }
    }
}
