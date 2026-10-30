// What scripts have locked on the player: the control groups of `DisablePlayerControls`,
// a beast form, and the three switches of `SetInChargen`. Sources: the Creation Kit wiki
// "SetInChargen - Game" and the `sTweenDisabledMessage` and `sCharGenControlsDisabled`
// rows of "Category:Settings". See docs/engine/papyrus-script-state.md#player-controls.

import Foundation

/// One argument of `DisablePlayerControls`, in argument order.
nonisolated public enum PlayerControlGroup: String, CaseIterable, Hashable, Sendable {
    case movement = "Movement"
    case fighting = "Fighting"
    case camSwitch = "CamSwitch"
    case looking = "Looking"
    case sneaking = "Sneaking"
    case menu = "Menu"
    case activate = "Activate"
    case journal = "Journal"
}

/// Why the game turned down one player action, so the shell can show the matching text.
nonisolated public enum PlayerControlRefusal: Equatable, Sendable {
    /// No text: the control is off and no message was asked for.
    case silent
    /// `sTweenDisabledMessage`: the character menus are locked.
    case menusDisabled
    /// `sCharGenControlsDisabled`: character creation asked for a message.
    case chargenControls
    /// `sCantQuickSave` and `sCantQuickLoad`: a menu pauses the game.
    case quickSaveWhilePaused
    case quickLoadWhilePaused
}

nonisolated public struct PlayerControlLocks: Equatable, Sendable {
    public var disabled: Set<PlayerControlGroup> = []
    public var isBeastForm = false
    /// `sCantSaveNow`; the save service reads it.
    public var savingDisabled = false
    /// `sNoWaitDefault` and `sNoSleepDefault`; the rest rule reads it.
    public var waitingDisabled = false
    /// `abShowControlsDisabledMessage`: a locked control shows `sCharGenControlsDisabled`.
    public var showsChargenMessage = false

    public static let none = Self()

    public init(
        disabled: Set<PlayerControlGroup> = [], isBeastForm: Bool = false,
        savingDisabled: Bool = false, waitingDisabled: Bool = false,
        showsChargenMessage: Bool = false
    ) {
        self.disabled = disabled
        self.isBeastForm = isBeastForm
        self.savingDisabled = savingDisabled
        self.waitingDisabled = waitingDisabled
        self.showsChargenMessage = showsChargenMessage
    }

    /// Why a control of `group` is refused, or nil when it is free. A beast form locks the
    /// character menus as a script would (UESP "Skyrim:Lycanthropy").
    public func refusal(for group: PlayerControlGroup, beastLocked: Bool = false)
        -> PlayerControlRefusal?
    {
        let locked = disabled.contains(group)
        if !locked, beastLocked, isBeastForm {
            return group == .menu ? .menusDisabled : .silent
        }
        guard locked else { return nil }
        if showsChargenMessage {
            return .chargenControls
        }
        return group == .menu ? .menusDisabled : .silent
    }
}
