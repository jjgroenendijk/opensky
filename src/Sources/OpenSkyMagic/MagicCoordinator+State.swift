// The coordinator's per-system state, grouped so each group names its own types.

public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMagicInterface

extension MagicCoordinator {
    /// The game settings the Magic port reads.
    public var holdSettings: MagicHoldSettings {
        rules.holds
    }

    struct CastingState {
        /// The hands pressed last frame, so a press during a shout is refused once.
        var castPressed: Set<SpellHand> = []
        /// Each casting hand as the cues saw it last frame; an idle hand is left out.
        var castingViews: [CastSlot: CastingHandView] = [:]
        /// Each casting hand as the graph event rule saw it last frame.
        var graphHands: [CastSlot: CastingGraphHand] = [:]
        /// Start events raised a step after their cast began, once the graph is casting.
        var pendingStarts: [(slot: CastSlot, event: String)] = []
        /// The last graph event a cast raised, for the readout.
        var lastGraphEvent: String?
        var releaseLatch = SpellReleaseLatch()
        /// Hands pressed while the hands were away; each stays still until released.
        var sheathedPress: Set<SpellHand> = []
        var wasWeaponsDrawn: Bool?
        /// The spell whose art each hand shows now.
        var handArt: [CastSlot: ReferenceKey] = [:]
        var castingCueCount = 0
        var lastCastingCue: String?
        /// An index into the player's known spells. Clamped on read.
        var selection = 0
        var lastCastingAction = CastingActionOutcome.idle
    }

    struct ShoutState {
        var wasShoutHeld = false
        /// Seconds the readout's Shout button still holds the key.
        var panelShoutHold: Float?
        /// The shout the machine is voicing, fixed at the press.
        var voicedShout: ReferenceKey?
        var lastShout = ShoutOutcome.idle
    }

    struct RuneState {
        /// Runes waiting on the ground, oldest first. Not saved.
        var runes: [PlacedRune] = []
        var detonatedRunes = 0
    }

    struct EnchantingMemory {
        var lastEnchanting = EnchantingOutcome.idle
        var profiles = ItemEnchantmentProfileCache()
    }
}
