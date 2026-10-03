// The world-object data a use-key target carries beyond its name: a workbench's
// bench data and keywords, and the activation event a station raises.
// See docs/engine/crafting.md.

import OpenSkyFormatsESM

/// A FURN base with `WBDT`, as the use key sees it.
nonisolated public struct CraftingStation: Equatable, Sendable {
    public let workbench: Workbench
    /// `KWDA` as written, relative to the base's plugin. A recipe's `BNAM` names one.
    public let keywords: [FormID]

    public init(workbench: Workbench, keywords: [FormID]) {
        self.workbench = workbench
        self.keywords = keywords
    }
}

/// One use-key activation of a crafting station. The plain `InteractionEvent` is
/// still published beside it.
nonisolated public struct CraftingActivationEvent: Equatable, Sendable {
    public let interaction: PlacedInteraction
    public let station: CraftingStation

    /// The event a use-key press on `interaction` raises, or nil when it is no station.
    public init?(interaction: PlacedInteraction) {
        guard interaction.action == .use, let station = interaction.station else { return nil }
        self.interaction = interaction
        self.station = station
    }
}

nonisolated extension InteractionAction {
    /// The label a harvested plant shows in place of `Harvest`. OpenSky's wording.
    public static let harvestedLabel = "Harvested"
}

nonisolated extension PlacedInteraction {
    /// This interaction with its prompt label, and optionally its name, replaced.
    public func relabelled(_ label: String, name newName: String? = nil) -> PlacedInteraction {
        PlacedInteraction(
            reference: reference,
            base: base,
            position: position,
            name: newName ?? name,
            action: action,
            actionLabel: label,
            sounds: sounds,
            voiceType: voiceType,
            station: station,
            produce: produce,
            lock: lock
        )
    }
}
