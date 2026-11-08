// The Traps section readout over plain snapshots: trigger states, the enable chain,
// and the hazard lines.

import OpenSkyFormatsESM
@testable import OpenSkyPhysics
import Testing

struct TrapReadoutTests {
    static let plate = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x10)

    @Test func listsTriggersChainAndHazards() {
        let snapshot = TrapControlSnapshot(
            isAvailable: true,
            triggers: [TrapTriggerRow(
                key: Self.plate, name: "Plate", scripts: ["pressureplate: Ready"], occupants: 1,
                isEnabled: true
            )],
            selected: Self.plate,
            chain: [
                TrapChainLink(name: "Flames", isEnabled: false, isOppositeOfParent: false),
                TrapChainLink(name: "Plate", isEnabled: true, isOppositeOfParent: true)
            ],
            hazards: [TrapHazardRow(
                name: "Fire", remainingLifetime: nil, lastHitTargets: 1, lastHitEffects: 2
            )],
            hazardHits: 4,
            lastText: "Fired Plate."
        )
        let text = TrapReadout.text(for: snapshot)
        #expect(text.contains("  Plate: pressureplate: Ready, inside 1"))
        #expect(text.contains("Selected: Plate: pressureplate: Ready, inside 1"))
        #expect(text.contains("Enable chain: Flames off <- Plate on (opposite)"))
        #expect(text.contains("Hazards: 1, hits 4"))
        #expect(text.contains("  Fire: stays with cell, last hit 1 actors, 2 effects"))
    }

    @Test func unavailableShowsTheReason() {
        #expect(TrapReadout.text(for: .unavailable) == "No scripts running.")
    }
}
