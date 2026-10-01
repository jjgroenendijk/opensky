/// Applying one landed spell. A projectile, a target-actor cast and a beam land the
/// same way, so the session implements it once.
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
