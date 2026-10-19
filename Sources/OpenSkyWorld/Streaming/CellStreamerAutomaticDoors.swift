// Automatic doors: the CK wiki "Door" page says such a door is activated when the
// player enters its space rather than by the use key. See docs/engine/interaction.md.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

extension CellStreamer {
    /// Activates each automatic door whose area the feet entered this frame. A door
    /// fires once per entry and again only after the player leaves its area.
    public func updateAutomaticDoors(feet: SIMD3<Float>?) {
        guard let feet, transitionInFlight == nil else {
            automaticDoorOccupancy = nil
            return
        }
        let inside = residentScenes.flatMap { scene in
            scene.interactions.values.filter { $0.automaticArea?.contains(feet) == true }
        }
        let previous = automaticDoorOccupancy
        automaticDoorOccupancy = Set(inside.map(\.reference))
        guard let previous else { return }
        guard
            let entered = inside.sorted(by: { $0.reference.rawValue < $1.reference.rawValue })
                .first(where: { !previous.contains($0.reference) })
        else { return }
        activate(InteractionTarget(interaction: entered, hitPosition: feet, distance: 0))
    }
}
