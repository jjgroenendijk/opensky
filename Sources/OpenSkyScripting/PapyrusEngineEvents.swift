// The Papyrus events the engine sends to scripts. Every sender takes its name from here,
// so `openskycli gaps` can list the events scripts handle and the engine never sends.
// A SwiftLint rule rejects an event-name literal elsewhere in the scripting module.

import Foundation

nonisolated public enum PapyrusEngineEvents: Sendable {
    public static let onInit = "OnInit"
    public static let onCellAttach = "OnCellAttach"
    public static let onLoad = "OnLoad"
    public static let onCellLoad = "OnCellLoad"
    public static let onAnimationEvent = "OnAnimationEvent"
    public static let onActivate = "OnActivate"
    public static let onTriggerEnter = "OnTriggerEnter"
    public static let onTriggerLeave = "OnTriggerLeave"
    public static let onUpdate = "OnUpdate"
    public static let onUpdateGameTime = "OnUpdateGameTime"
    public static let onHit = "OnHit"
    public static let onDying = "OnDying"
    public static let onDeath = "OnDeath"
    public static let onRaceSwitchComplete = "OnRaceSwitchComplete"
    public static let onPackageStart = "OnPackageStart"
    public static let onPackageEnd = "OnPackageEnd"
    public static let onPackageChange = "OnPackageChange"
    public static let onBeginState = "OnBeginState"
    public static let onEndState = "OnEndState"
    public static let onUnload = "OnUnload"
    public static let onCellDetach = "OnCellDetach"
    public static let onPlayerLoadGame = "OnPlayerLoadGame"
    public static let onLocationChange = "OnLocationChange"
    public static let onItemAdded = "OnItemAdded"
    public static let onItemRemoved = "OnItemRemoved"
    public static let onObjectEquipped = "OnObjectEquipped"
    public static let onObjectUnequipped = "OnObjectUnequipped"
    public static let onCombatStateChanged = "OnCombatStateChanged"
    public static let onEffectStart = "OnEffectStart"
    public static let onEffectFinish = "OnEffectFinish"
    public static let onMagicEffectApply = "OnMagicEffectApply"
    public static let onTranslationAlmostComplete = "OnTranslationAlmostComplete"
    public static let onTranslationComplete = "OnTranslationComplete"
    public static let onTranslationFailed = "OnTranslationFailed"
    public static let onOpen = "OnOpen"
    public static let onClose = "OnClose"
    public static let onLockStateChanged = "OnLockStateChanged"
    public static let onContainerChanged = "OnContainerChanged"

    /// Every event above, lowercased, as Papyrus matches names.
    public static let sent: Set<String> = Set([
        onInit, onCellAttach, onLoad, onCellLoad, onAnimationEvent, onActivate, onTriggerEnter,
        onTriggerLeave, onUpdate, onUpdateGameTime, onHit, onDying, onDeath, onRaceSwitchComplete,
        onPackageStart, onPackageEnd, onPackageChange, onBeginState, onEndState, onUnload,
        onCellDetach, onPlayerLoadGame, onLocationChange, onItemAdded, onItemRemoved,
        onObjectEquipped, onObjectUnequipped, onCombatStateChanged, onEffectStart, onEffectFinish,
        onMagicEffectApply, onTranslationAlmostComplete, onTranslationComplete, onTranslationFailed,
        onOpen, onClose, onLockStateChanged,
        onContainerChanged
    ].map { $0.lowercased() })
}
