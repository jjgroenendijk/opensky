// Developer > Agent Control destination panel (docs/tools/agent-control.md).

import AppKit
import OpenSkyAgentControl

final class AgentControlPanelViewController: InspectorPanelViewController {
    let controlSection = AgentControlSection()

    weak var provider: (any AgentControlProviding)? {
        didSet {
            controlSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [controlSection]
    }
}
