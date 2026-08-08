// One landed blow as script code sees it (issue #375, roadmap item 15.8), and
// the seam the three combat runtimes report it through.
//
// The value carries exactly the seven `OnHit` parameters the Creation Kit wiki
// documents, in its vocabulary rather than in the melee runtime's, because that
// is what the world runtime turns straight into event arguments. Filling it is
// the job of whichever runtime resolved the hit — only that runtime knows
// whether the swing was a bash, and only it knows which weapon record was in
// hand.
//
// ## Why the reporting method has a default implementation
//
// `MeleeCombatWorld`, `ProjectileWorld` and `CombatLoopWorld` are the seams the
// acceptance tests drive against fakes with no renderer and no game data. A
// fake that does not care about scripts should not have to write an empty
// method to keep compiling, and — more importantly — a fake that *does* care
// should opt in explicitly rather than inherit a behaviour. So the protocol
// carries one method with a do-nothing default, and the session overrides it.
// Returning the queued-event count rather than nothing is what lets a test
// assert that a hit reached the scripts it was supposed to reach.
//
// Documented in docs/engine/combat.md.

import Foundation

/// One blow, as `OnHit(ObjectReference akAggressor, Form akSource, Projectile
/// akProjectile, bool abPowerAttack, bool abSneakAttack, bool abBashAttack,
/// bool abHitBlocked)` spells it
/// (<https://www.creationkit.com/index.php?title=OnHit_-_ObjectReference>).
nonisolated struct ScriptHitEvent: Equatable, Sendable {
    /// What was hit. Not necessarily an actor: the event is declared on
    /// `ObjectReference`, so a scripted crate takes it too.
    let target: ReferenceKey
    /// Who swung or fired.
    let aggressor: ReferenceKey
    /// The WEAP, SPEL, EXPL, INGR, ALCH or ENCH behind the hit, or nil where
    /// the path names none — an unarmed blow, above all.
    let source: FormID?
    /// The PROJ that struck, or nil for a melee hit. The wiki records that
    /// vanilla leaves this `None` for an actor target even for an arrow; this
    /// engine fills it in whenever the projectile runtime knows it, which is
    /// more informative and cannot break a handler that checks for `None`
    /// first.
    let projectile: FormID?
    let isPowerAttack: Bool
    let isSneakAttack: Bool
    let isBashAttack: Bool
    let isBlocked: Bool

    init(
        target: ReferenceKey,
        aggressor: ReferenceKey,
        source: FormID? = nil,
        projectile: FormID? = nil,
        isPowerAttack: Bool = false,
        isSneakAttack: Bool = false,
        isBashAttack: Bool = false,
        isBlocked: Bool = false
    ) {
        self.target = target
        self.aggressor = aggressor
        self.source = source
        self.projectile = projectile
        self.isPowerAttack = isPowerAttack
        self.isSneakAttack = isSneakAttack
        self.isBashAttack = isBashAttack
        self.isBlocked = isBlocked
    }
}

/// How a combat runtime tells the script layer that a blow landed.
@MainActor
protocol ScriptHitReporting: AnyObject {
    /// Delivers one landed blow to the scripts attached to its target.
    ///
    /// - Returns: how many `OnHit` events were queued. Zero is the ordinary
    ///   answer for an unscripted target and for a session with no VM, and is
    ///   never an error.
    @discardableResult
    func reportScriptHit(_ hit: ScriptHitEvent) -> Int
}

nonisolated extension ScriptHitReporting {
    /// A world with no script layer behind it reports nothing, which is what
    /// every acceptance fake wants and what a synthetic scene genuinely is.
    @discardableResult
    func reportScriptHit(_ hit: ScriptHitEvent) -> Int {
        0
    }
}
