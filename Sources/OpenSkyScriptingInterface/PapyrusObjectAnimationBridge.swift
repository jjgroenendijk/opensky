import Foundation
public import OpenSkyFormatsESM

/// The object behaviour graphs of the running game. The app answers it.
public protocol PapyrusObjectAnimationBridge: AnyObject {
    /// Raises `event` on the object's graph. False when the object runs no graph.
    func playAnimation(_ event: String, on reference: ReferenceKey) -> Bool
    /// A token the app answers through `PapyrusScheduler.answer` when the graph
    /// fires `event`. Nil when the object runs no graph.
    func awaitAnimationEvent(_ event: String, on reference: ReferenceKey) -> UInt64?
    /// A graph variable as a Papyrus value. Nil when the object runs no graph or the
    /// graph declares no such variable.
    func animationVariable(_ name: String, on reference: ReferenceKey) -> PapyrusValue?
    /// False when the object runs no graph or the graph declares no such variable.
    func setAnimationVariable(_ name: String, to value: PapyrusValue, on reference: ReferenceKey)
        -> Bool
    /// Raises `event` on every sub-graph of the actor. False when none declares it.
    func playSubGraphAnimation(_ event: String, on actor: ReferenceKey) -> Bool
    /// Sets the variable on every sub-graph of the actor. False when none declares it.
    func setSubGraphFloatVariable(_ name: String, to value: Float, on actor: ReferenceKey)
        -> Bool
    /// The `GetOpenState` code of a door whose mesh sequences move it, opening and
    /// closing included, or 0 for a reference that cannot open. Nil for any other.
    func openStateCode(of reference: ReferenceKey) -> Int32?
}
