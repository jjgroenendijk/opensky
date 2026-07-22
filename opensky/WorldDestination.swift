// World-mode sidebar destinations: the extensible list of verification/control
// surfaces shown beside the live World view (AGENTS.md "Main-app verification
// surface"). Environment is the first entry; weather/particles/grass panels
// append here in M7.2-7.5 rather than adding new top-level items. Row order is
// `allCases`; each row carries `sidebarIdentifier` for UI tests + future work.

nonisolated enum WorldDestination: String, CaseIterable {
    case environment
    case uiLab

    /// Sidebar row title.
    var title: String {
        switch self {
        case .environment: "Environment"
        case .uiLab: "UI Lab"
        }
    }

    /// Stable accessibility identifier (UI tests, milestone acceptance).
    var sidebarIdentifier: String {
        "WorldDestination-\(rawValue)"
    }
}
