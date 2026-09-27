// M15 acceptance (issue #198): one continuous fight, driven by key and mouse
// events, through every combat and physics capability the milestone claims.
//
// The gate statement in one run: a weapon is drawn, a swing lands and takes
// health off the live actor values, a blocked blow is reduced by the pinned
// formula, an arrow flies where it was aimed and lands the killing hit, the
// death hands the skeleton to the constraint-solved ragdoll, the corpse is
// looted without losing an item, dropped clutter settles, and a save and load
// brings the dead actor, its emptied inventory and the settled crate all back.
//
// Every step asserts what the engine holds, not just that the call returned:
// which state each graph entered, what the actor values read, which annotation
// fired the contact, where the arrow ended, how many bodies the ragdoll spawned,
// and what the store carried through the save. The pixel half is
// `M15AcceptanceRenderTests`, the panel half is `M15AcceptancePanelTests` and
// the vanilla half is `M15AcceptanceRealDataTests`; all three are gated, and
// everything here runs on a device-less runner with no install.

import Foundation
@testable import opensky
import simd
import Testing

@MainActor
struct M15AcceptanceTests {
    // MARK: - The route

    /// The gate itself. One session fights the whole fight and every step is
    /// checked before the next one runs, so a failure names the step rather
    /// than leaving an end state to reverse-engineer.
    @Test("one route fights the whole M15 loop through the shipping input path")
    func theRouteFightsTheWholeCombatLoop() throws {
        let chain = try Chain()

        try Self.standStill(chain)
        try Self.drawTheWeapon(chain)
        try Self.angerTheOpponent(chain)
        try Self.landASwing(chain)
        try Self.blockAnIncomingBlow(chain)
        try Self.switchToTheBow(chain)
        try Self.landTheKillingArrow(chain)
        try Self.watchTheRagdollCollapse(chain)
        try Self.lootTheCorpse(chain)
        try Self.settleTheClutter(chain)
        try Self.saveAndLoad(chain)
        Self.expectEveryStateWasEntered(chain)
    }
}
