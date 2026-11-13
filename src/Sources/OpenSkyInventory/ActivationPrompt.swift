// The verb the crosshair shows for a use-key target, from the `sTake`, `sSearch`, and
// related string settings. A theft shows the red `sSteal` or `sStealFrom` verb, a
// sneaking player sees `sPickpocket` on an actor, and an open door `sClose`.
// See docs/engine/interaction.md.

public import OpenSkyGameData
public import OpenSkyWorldInterface

nonisolated public enum ActivationText: String, GameSettingTextKey {
    case activate = "sActivate"
    case open = "sOpen"
    case close = "sClose"
    case use = "sUse"
    /// Put after the name of a bed someone else owns.
    case owned = "sOwned"
    case search = "sSearch"
    case harvest = "sHarvest"
    case take = "sTake"
    case talk = "sTalk"
    case sleep = "sFurnitureSleep"
    case sit = "sSit"
    case read = "sRead"
    /// The game's text carries its own red `<font>` markup.
    case steal = "sSteal"
    case stealFrom = "sStealFrom"
    case pickpocket = "sPickpocket"
    /// An automatic load door, named from a distance.
    case to = "sTo"

    public var fallback: String {
        switch self {
        case .activate: "Activate"
        case .open: "Open"
        case .close: "Close"
        case .use: "Use"
        case .owned: "Owned"
        case .search: "Search"
        case .harvest: "Harvest"
        case .take: "Take"
        case .talk: "Talk to"
        case .sleep: "Sleep"
        case .sit: "Sit"
        case .read: "Read"
        case .steal: "<font color='#FF0000'>Steal</font>"
        case .stealFrom: "<font color='#FF0000'>Steal from</font>"
        case .pickpocket: "<font color='#FF0000'>Pickpocket</font>"
        case .to: "To"
        }
    }
}

/// What the verb depends on beyond the interaction itself.
nonisolated public struct ActivationPromptContext: Equatable, Sendable {
    public var isBook = false
    /// Taking the item, or from the container, would be a theft.
    public var isTheft = false
    public var isPlayerSneaking = false
    /// A door or other openable target that is open now.
    public var isOpen = false

    public init(
        isBook: Bool = false, isTheft: Bool = false, isPlayerSneaking: Bool = false,
        isOpen: Bool = false
    ) {
        self.isBook = isBook
        self.isTheft = isTheft
        self.isPlayerSneaking = isPlayerSneaking
        self.isOpen = isOpen
    }
}

nonisolated public enum ActivationPrompt {
    /// The verb for `interaction`, or nil when its base authors its own (`ACTI` `RNAM`).
    public static func text(
        for interaction: PlacedInteraction, context: ActivationPromptContext
    ) -> ActivationText? {
        guard !interaction.hasLabelOverride else { return nil }
        switch interaction.action {
        case .take:
            if context.isTheft {
                return .steal
            }
            return context.isBook ? .read : .take
        case .search: return context.isTheft ? .stealFrom : .search
        case .open:
            if interaction.automaticArea != nil {
                return .to
            }
            return context.isOpen ? .close : .open
        case .harvest: return .harvest
        case .talk: return context.isPlayerSneaking ? .pickpocket : .talk
        case .use:
            if interaction.isBed {
                return .sleep
            }
            return interaction.seats.isEmpty ? .use : .sit
        case .activate: return .activate
        }
    }

    /// `interaction` with the verb from `texts`.
    public static func labelled(
        _ interaction: PlacedInteraction,
        context: ActivationPromptContext,
        texts: GameSettingTexts<ActivationText>
    ) -> PlacedInteraction {
        guard let text = text(for: interaction, context: context) else { return interaction }
        if text == .sleep, context.isTheft {
            return interaction.relabelled(
                texts[text], name: "\(interaction.name) (\(texts[.owned]))"
            )
        }
        return interaction.relabelled(texts[text])
    }
}
