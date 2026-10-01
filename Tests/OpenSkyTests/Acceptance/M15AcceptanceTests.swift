// Combat acceptance: one key-and-mouse fight. Draw, hit, block by formula,
// arrow kill, ragdoll death, loot, settled clutter, then save and load bring
// it all back. Each step checks engine state. Pixel, panel, and real-data
// halves are gated; this runs without a device or install.

import Foundation
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
