// World > Container Menu: the M12.2.3 verification surface. Two sections — the
// merchant nomination the barter mode needs before it has a merchant at all,
// and the menu itself.

import AppKit

final class ContainerMenuPanelViewController: InspectorPanelViewController {
    let merchantSection = ContainerMerchantSection()
    let menuSection = ContainerMenuSection()

    weak var provider: (any ContainerMenuControlProviding)? {
        didSet {
            merchantSection.provider = provider
            menuSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [merchantSection, menuSection]
    }
}
