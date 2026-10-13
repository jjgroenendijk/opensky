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

    /// Every event above, lowercased, as Papyrus matches names.
    public static let sent: Set<String> = Set([
        onInit, onCellAttach, onLoad, onCellLoad, onAnimationEvent, onActivate, onTriggerEnter,
        onTriggerLeave, onUpdate, onUpdateGameTime, onHit, onDying, onDeath, onRaceSwitchComplete,
        onPackageStart, onPackageEnd, onPackageChange, onBeginState, onEndState
    ].map { $0.lowercased() })
}
