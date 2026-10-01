// World > Container Menu. Two sections: the merchant nomination that barter
// mode needs, and the menu itself.

import AppKit
import OpenSkyMenus

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
