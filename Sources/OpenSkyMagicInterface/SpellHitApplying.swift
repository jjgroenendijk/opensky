/// Applying one landed spell, wherever it came from.
///
/// Its own protocol for the reason `ScriptHitReporting` is: a projectile, a
/// target-actor cast and a concentration beam all land the same way, and the
/// session implements the answer once for all three (issue #471).
@MainActor
public protocol SpellHitApplying: AnyObject {
    /// Applies one landed spell to the actors it reached.
    ///
    /// - Returns: what was applied. `SpellHitReport.none` when the session has
    ///   no effect runtime, which a synthetic scene is, so a spell that could
    ///   not be applied is reported rather than counted as landed.
    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport
}
