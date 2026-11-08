// Automatic doors: the CK wiki "Door" page says such a door is activated when the
// player enters its space rather than by the use key. See docs/engine/interaction.md.

import Foundation
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
            scene.interactions.values.filter {
                $0.automaticArea?.contains(feet) == true
                    && simd_distance($0.position, feet) <= doors.autoActivateDistance
            }
        }
        let previous = automaticDoorOccupancy
        automaticDoorOccupancy = Set(inside.map(\.reference))
        guard
            let previous,
            let entered = inside.sorted(by: { $0.reference.rawValue < $1.reference.rawValue })
                .first(where: { !previous.contains($0.reference) })
        else { return }
        activate(InteractionTarget(interaction: entered, hitPosition: feet, distance: 0))
    }

    /// The nearest automatic door within `fAutoDoorDisplayDistance`, which the HUD names
    /// when the crosshair is on nothing else.
    func nearestAutomaticDoor(to origin: SIMD3<Float>) -> InteractionTarget? {
        let range = doors.autoDisplayDistance
        let near = residentScenes.flatMap { scene in
            scene.interactions.values.filter {
                $0.automaticArea != nil && simd_distance($0.position, origin) <= range
            }
        }
        let nearest = near.min { lhs, rhs in
            let left = simd_distance(lhs.position, origin)
            let right = simd_distance(rhs.position, origin)
            return left == right ? lhs.reference.rawValue < rhs.reference.rawValue : left < right
        }
        return nearest.map {
            InteractionTarget(
                interaction: $0, hitPosition: $0.position,
                distance: simd_distance($0.position, origin)
            )
        }
    }
}
