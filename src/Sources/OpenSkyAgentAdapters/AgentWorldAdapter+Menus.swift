// The open menu as rows an agent can read and select by label. Selection moves
// through the same menu input path as the arrow keys.

import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyRendering
import OpenSkySessionInterface

public struct AgentMenuRows: Equatable {
    public let menu: String
    public let rows: [String]
    public let selected: Int
}
